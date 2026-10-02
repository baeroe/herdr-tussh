#!/usr/bin/env bash
# Regenerates the README screenshots in docs/screenshots/ from the VHS tapes in docs/tapes/.
#
#   bash docs/screenshots.sh            # all tapes
#   bash docs/screenshots.sh alerts     # only docs/tapes/alerts.tape
#
# Needs herdr, go, jq, vhs (brew install vhs; pulls ttyd and ffmpeg), optionally pngquant/oxipng, and a
# checkout of https://github.com/baeroe/tussh (default: ../tussh, override with TUSSH_REPO). The tussh demo
# data and its demo TUI (docs/demo in that repo) are reused, so the screenshots match the tussh README.
#
# Nothing touches your herdr: a separate herdr server runs with its own HOME in a throwaway sandbox (its
# own config, socket and sessions), with only this plugin linked, and is stopped afterwards. tussh also
# runs against a sandbox (own config/state dirs, a file keyring, *.example hosts).
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
tussh_repo=$(cd "${TUSSH_REPO:-$repo/../tussh}" && pwd)
herdr_bin=$(command -v herdr || echo "$HOME/.local/bin/herdr")
cd "$repo"

# short path: herdr's unix sockets live under $HOME/.config/herdr
sandbox=$(cd "$(mktemp -d /tmp/hd.XXXXXX)" && pwd -P)
mcp_pid=
cleanup() {
	exec 3>&- 2>/dev/null || true
	[ -n "$mcp_pid" ] && kill "$mcp_pid" 2>/dev/null || true
	[ -x "$sandbox/env.sh" ] && "$sandbox/env.sh" herdr server stop >/dev/null 2>&1 || true
	rm -rf "$sandbox"
}
trap cleanup EXIT

# --- tussh demo data (same as `make screenshots` in the tussh repo) ---
home="$sandbox/h"
mkdir -p "$sandbox/bin" "$home/.local/bin" "$home/.ssh" "$home/shop"/{src,public,config}
chmod 700 "$home/.ssh"
touch "$home/shop"/{composer.json,composer.lock,README.md}
cat >"$home/shop/docker-compose.yml" <<'EOF'
services:
  php:
    build: .
    volumes: [".:/var/www/shop"]
  nginx:
    image: nginx:1.27
    ports: ["8080:80"]
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_DATABASE: shop
EOF
export TUSSH_CONFIG_DIR="$home/.config/tussh" TUSSH_STATE_DIR="$home/.local/state/tussh"
export TUSSH_KEYRING="file:$sandbox/keyring.json" TUSSH_SSH_DIR="$home/.ssh"
export TUSSH_NO_NOTIFY=1 TUSSH_APPROVAL_TIMEOUT=900
(cd "$tussh_repo" && go build -trimpath -o "$home/.local/bin/tussh" . &&
	go build -trimpath -o "$sandbox/bin/tussh-demo" docs/demo/tui.go && go run docs/demo/seed.go)
ln -s "$herdr_bin" "$sandbox/bin/herdr"

# the environment of the sandboxed herdr (server, panes and plugin commands inherit it)
cat >"$sandbox/env.sh" <<EOF
#!/bin/sh
cd "$home/shop"
exec env -i HOME="$home" PATH="$sandbox/bin:$home/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \\
	TERM=xterm-256color SHELL=/bin/zsh LANG=en_US.UTF-8 \\
	TUSSH_CONFIG_DIR="$TUSSH_CONFIG_DIR" TUSSH_STATE_DIR="$TUSSH_STATE_DIR" TUSSH_KEYRING="$TUSSH_KEYRING" \\
	TUSSH_SSH_DIR="$TUSSH_SSH_DIR" TUSSH_NO_NOTIFY=1 TUSSH_APPROVAL_TIMEOUT=900 TUSSH_BIN=tussh-demo "\$@"
EOF
chmod +x "$sandbox/env.sh"

mkdir -p "$home/.config/herdr"
cat >"$home/.config/herdr/config.toml" <<'EOF'
onboarding = false

[theme]
name = "dracula"

[terminal]
new_cwd = "~/shop"

[update]
version_check = false
manifest_check = false

[[keys.command]]
key = "prefix+h"
type = "plugin_action"
command = "herdr-tussh.open-tussh"
description = "tussh"

[[keys.command]]
key = "prefix+a"
type = "plugin_action"
command = "herdr-tussh.alerts"
description = "tussh alerts"
EOF
# a neutral prompt for the shell panes
printf "PROMPT='%%F{cyan}%%~%%f %%F{magenta}❯%%f '\n" >"$home/.zshrc"

start_herdr() {
	"$sandbox/env.sh" herdr server >>"$sandbox/server.log" 2>&1 &
	for _ in $(seq 50); do
		"$sandbox/env.sh" herdr status server 2>/dev/null | grep -q 'status: running' && break
		sleep 0.2
	done
	"$sandbox/env.sh" herdr plugin link "$repo" >/dev/null
}
stop_herdr() {
	"$sandbox/env.sh" herdr server stop >/dev/null 2>&1 || true
	rm -rf "$home/.config/herdr/session.json" "$home/.config/herdr/session-snapshots"
	sleep 1
}

# a real tussh MCP session that leaves two approval requests pending
mkfifo "$sandbox/mcp.in"
"$sandbox/env.sh" tussh mcp <"$sandbox/mcp.in" >"$sandbox/mcp.out" 2>&1 &
mcp_pid=$!
exec 3>"$sandbox/mcp.in"
send() { printf '%s\n' "$1" >&3; }
send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude-code","version":"2.1.4"}}}'
send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
send '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"run_command","arguments":{"connection":"shop-db","command":"mysql shop -e \"DELETE FROM sessions WHERE updated_at < NOW() - INTERVAL 30 DAY\"","justification":"The sessions table has 4 GB of stale rows"}}}'
sleep 1
send '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"run_command","arguments":{"connection":"shop-prod","command":"systemctl restart php8.3-fpm","justification":"PHP-FPM workers hang since the deploy and /checkout returns 502. A restart frees them."}}}'
for _ in $(seq 50); do
	[ "$(find "$TUSSH_STATE_DIR/approvals" -name '*.json' ! -name '*.decision.json' 2>/dev/null | wc -l)" -ge 2 ] && break
	sleep 0.2
done

export HERDR_DEMO="$sandbox/env.sh"
tapes=("$@")
if [ ${#tapes[@]} -eq 0 ]; then
	for f in docs/tapes/*.tape; do
		[ "$(basename "$f")" = config.tape ] || tapes+=("$(basename "$f" .tape)")
	done
fi
for t in "${tapes[@]}"; do
	echo "== $t"
	start_herdr # a fresh herdr session per tape
	vhs "docs/tapes/$t.tape"
	stop_herdr
done
rm -rf .vhs

cd docs/screenshots
command -v pngquant >/dev/null && pngquant --force --skip-if-larger --quality 80-95 --ext .png ./*.png || true
command -v oxipng >/dev/null && oxipng -q -o 4 --strip safe ./*.png || true
ls -lh
