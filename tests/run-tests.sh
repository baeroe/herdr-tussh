#!/usr/bin/env bash
# Hermetic test suite: HERDR_BIN_PATH points at a fake herdr that serves
# fixture `pane list` JSON and records every other call's argv. No running
# herdr needed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/toggle-tussh.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE="$TMP/herdr"
LOG="$TMP/calls.log"
LIST="$TMP/list.json"
NOJQ="$TMP/nojq-bin"
mkdir -p "$NOJQ"

TESTS=0
FAILURES=0
pass() { TESTS=$((TESTS + 1)); printf 'ok   %s\n' "$1"; }
fail() { TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); printf 'FAIL %s\n' "$1"; }

# Absolute paths only, so the fake also works with an empty PATH (jq missing).
cat > "$FAKE" <<'FAKE'
#!/bin/bash
if [ "$1" = pane ] && [ "$2" = list ]; then
  [ "${FAKE_LIST_FAIL:-0}" = 1 ] && exit 1
  /bin/cat "$FAKE_LIST"
  exit 0
fi
printf '%s\n' "$*" >> "$FAKE_LOG"
FAKE
chmod +x "$FAKE"

OPEN_SPLIT="plugin pane open --plugin herdr-tussh --entrypoint tussh --placement split --direction right --focus"
OPEN_TAB="plugin pane open --plugin herdr-tussh --entrypoint tussh --placement tab --focus"

# run_case NAME MODE LIST_JSON EXPECTED_CALLS [ENV...]
# EXPECTED_CALLS is the exact newline-separated argv log (pane list excluded).
run_case() {
  local name="$1" mode="$2" list="$3" expect="$4"
  shift 4
  printf '%s' "$list" > "$LIST"
  : > "$LOG"
  env FAKE_LIST="$LIST" FAKE_LOG="$LOG" HERDR_BIN_PATH="$FAKE" "$@" \
    /bin/bash "$SCRIPT" "$mode" >/dev/null 2>&1
  local got
  got="$(/bin/cat "$LOG")"
  if [ "$got" = "$expect" ]; then
    pass "$name"
  else
    fail "$name"
    printf '     expected: %s\n     got:      %s\n' "$(printf '%s' "$expect" | tr '\n' ';')" "$(printf '%s' "$got" | tr '\n' ';')"
  fi
}

# --- fixtures ----------------------------------------------------------------

p() { printf '{"pane_id":"%s","tab_id":"%s","label":%s,"focused":%s}' "$1" "$2" "$3" "$4"; }
list() { local IFS=,; printf '{"id":"cli:pane:list","result":{"panes":[%s]}}' "$*"; }

NONE="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p2 w1:t1 null false)")"
HERE_UNFOCUSED="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p2 w1:t1 '"tussh"' false)")"
HERE_FOCUSED="$(list "$(p w1:p1 w1:t1 null false)" "$(p w1:p2 w1:t1 '"tussh"' true)")"
OTHER_TAB="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p3 w1:t2 '"tussh"' false)")"
OTHER_WS="$(list "$(p w1:p1 w1:t1 null true)" "$(p w2:p1 w2:t1 '"tussh"' false)")"
UNSAFE="$(list "$(p w1:p1 w1:t1 null true)" "$(p -rf w1:t1 '"tussh"' false)")"
UNSAFE_TAB="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p3 --all '"tussh"' false)")"
OTHER_LABEL="$(list "$(p w1:p1 w1:t1 null true)" "$(p w1:p2 w1:t1 '"lazygit"' false)")"
NO_FOCUS="$(list "$(p w1:p1 w1:t1 null false)" "$(p w1:p2 w1:t1 '"tussh"' false)")"

# --- static checks -----------------------------------------------------------

if bash -n "$SCRIPT"; then pass "script passes bash -n"; else fail "script passes bash -n"; fi

# tomllib needs Python 3.11+; skip on older interpreters (e.g. macOS /usr/bin/python3).
if ! python3 -c 'import tomllib' 2>/dev/null; then
  printf 'skip herdr-plugin.toml is valid TOML (python3 without tomllib)\n'
elif python3 -c 'import tomllib, sys; tomllib.load(open(sys.argv[1], "rb"))' "$ROOT/herdr-plugin.toml"; then
  pass "herdr-plugin.toml is valid TOML"
else
  fail "herdr-plugin.toml is valid TOML"
fi

: > "$LOG"
if ! FAKE_LIST="$LIST" FAKE_LOG="$LOG" HERDR_BIN_PATH="$FAKE" bash "$SCRIPT" bogus >/dev/null 2>&1 && [ ! -s "$LOG" ]; then
  pass "rejects unknown mode without calling herdr"
else
  fail "rejects unknown mode without calling herdr"
fi

# --- split -------------------------------------------------------------------

run_case "split: no tussh pane -> open split" split "$NONE" "$OPEN_SPLIT"
run_case "split: tussh in focused tab, unfocused -> focus" split "$HERE_UNFOCUSED" $'pane zoom w1:p2 --on\npane zoom w1:p2 --off'
run_case "split: tussh focused -> close" split "$HERE_FOCUSED" "pane close w1:p2"
run_case "split: tussh only in another tab -> open split" split "$OTHER_TAB" "$OPEN_SPLIT"
run_case "split: other label is not tussh -> open split" split "$OTHER_LABEL" "$OPEN_SPLIT"
run_case "split: unsafe pane id -> open split" split "$UNSAFE" "$OPEN_SPLIT"
run_case "split: no focused pane -> open split" split "$NO_FOCUS" "$OPEN_SPLIT"
run_case "split: jq missing -> open split" split "$HERE_FOCUSED" "$OPEN_SPLIT" PATH="$NOJQ"
run_case "split: pane list fails -> open split" split "$HERE_FOCUSED" "$OPEN_SPLIT" FAKE_LIST_FAIL=1
run_case "split: garbage pane list -> open split" split "not json" "$OPEN_SPLIT"

# --- tab ---------------------------------------------------------------------

run_case "tab: no tussh pane -> open tab" tab "$NONE" "$OPEN_TAB"
run_case "tab: tussh in focused tab, unfocused -> focus" tab "$HERE_UNFOCUSED" $'pane zoom w1:p2 --on\npane zoom w1:p2 --off'
run_case "tab: tussh focused -> close" tab "$HERE_FOCUSED" "pane close w1:p2"
run_case "tab: tussh in another tab of same workspace -> tab focus" tab "$OTHER_TAB" "tab focus w1:t2"
run_case "tab: tussh in another workspace -> open tab" tab "$OTHER_WS" "$OPEN_TAB"
run_case "tab: unsafe pane id -> open tab" tab "$UNSAFE" "$OPEN_TAB"
run_case "tab: unsafe tab id -> open tab" tab "$UNSAFE_TAB" "$OPEN_TAB"
run_case "tab: jq missing -> open tab" tab "$OTHER_TAB" "$OPEN_TAB" PATH="$NOJQ"
run_case "tab: pane list fails -> open tab" tab "$OTHER_TAB" "$OPEN_TAB" FAKE_LIST_FAIL=1

# --- run-tussh.sh ------------------------------------------------------------

RUN="$ROOT/scripts/run-tussh.sh"
FAKEBIN="$TMP/fakebin"
FAKEHOME="$TMP/home"
mkdir -p "$FAKEBIN" "$FAKEHOME/.local/bin"
printf '#!/bin/sh\necho "path-tussh $*"\n' > "$FAKEBIN/tussh"
printf '#!/bin/sh\necho "home-tussh $*"\n' > "$FAKEHOME/.local/bin/tussh"
printf '#!/bin/sh\necho "override-tussh $*"\n' > "$TMP/override"
chmod +x "$FAKEBIN/tussh" "$FAKEHOME/.local/bin/tussh" "$TMP/override"

check_run() {
  local name="$1" expect="$2" got
  shift 2
  got="$(env "$@" /bin/sh "$RUN" alerts --popup </dev/null 2>/dev/null)"
  if [ "$got" = "$expect" ]; then pass "$name"; else fail "$name"; printf '     expected: %s\n     got:      %s\n' "$expect" "$got"; fi
}
check_run "run: tussh on PATH" "path-tussh alerts --popup" PATH="$FAKEBIN:/usr/bin:/bin" HOME="$FAKEHOME"
check_run "run: falls back to ~/.local/bin" "home-tussh alerts --popup" PATH="/usr/bin:/bin" HOME="$FAKEHOME"
check_run "run: TUSSH_BIN wins" "override-tussh alerts --popup" PATH="$FAKEBIN:/usr/bin:/bin" HOME="$FAKEHOME" TUSSH_BIN="$TMP/override"
if env PATH="/usr/bin:/bin" HOME="$TMP/empty" /bin/sh "$RUN" </dev/null >/dev/null 2>&1; then
  fail "run: missing tussh exits non-zero"
else
  pass "run: missing tussh exits non-zero"
fi

# --- alerts action -------------------------------------------------------------

# The manifest's alerts action command, executed against the fake herdr.
: > "$LOG"
alerts_cmd="$(sed -n '/^id = "alerts"/,/^command/p' "$ROOT/herdr-plugin.toml" | sed -n 's/^command = \["sh", "-c", "\(.*\)"\]$/\1/p' | sed 's/\\"/"/g')"
FAKE_LIST="$LIST" FAKE_LOG="$LOG" HERDR_BIN_PATH="$FAKE" sh -c "$alerts_cmd" >/dev/null 2>&1
if [ "$(/bin/cat "$LOG")" = "plugin pane open --plugin herdr-tussh --entrypoint alerts --focus" ]; then
  pass "alerts action opens the alerts popup entrypoint"
else
  fail "alerts action opens the alerts popup entrypoint"
  printf '     got: %s\n' "$(/bin/cat "$LOG")"
fi
if grep -q 'placement = "popup"' "$ROOT/herdr-plugin.toml" && grep -q '"alerts", "--popup"' "$ROOT/herdr-plugin.toml"; then
  pass "alerts entrypoint is a popup running tussh alerts --popup"
else
  fail "alerts entrypoint is a popup running tussh alerts --popup"
fi

# --- summary -----------------------------------------------------------------

printf '\n%d tests, %d failures\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
