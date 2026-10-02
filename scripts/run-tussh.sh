#!/bin/sh
# Start tussh. The herdr server may run without ~/.local/bin on PATH (it is only
# added in interactive shells), so fall back to the default install location.
# TUSSH_BIN overrides both.
if [ -n "${TUSSH_BIN:-}" ]; then
  bin="$TUSSH_BIN"
elif command -v tussh >/dev/null 2>&1; then
  bin="$(command -v tussh)"
elif [ -x "$HOME/.local/bin/tussh" ]; then
  bin="$HOME/.local/bin/tussh"
else
  printf 'tussh not found. Install it (see https://github.com/baeroe/tussh) into ~/.local/bin or PATH.\n' >&2
  printf 'Press Enter to close.' >&2
  read -r _
  exit 127
fi
exec "$bin" "$@"
