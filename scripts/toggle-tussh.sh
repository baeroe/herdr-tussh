#!/usr/bin/env bash
# Toggle tussh in a split pane or its own tab.
#
#   toggle-tussh.sh split   OPEN a split if there is no tussh pane in the
#                             focused tab, FOCUS it if present but unfocused,
#                             CLOSE it if it is the focused pane.
#   toggle-tussh.sh tab     Same, plus SWITCHTAB when tussh runs in another
#                             tab of the same workspace; otherwise OPEN a tab.
#
# Toggle logic adapted from herdr-lazydocker (MIT, Eren Çakar).
set -uo pipefail

mode="${1:-split}"
case "$mode" in
  split | tab) ;;
  *)
    printf 'usage: %s split|tab\n' "$0" >&2
    exit 2
    ;;
esac

herdr_bin="${HERDR_BIN_PATH:-herdr}"

open_tussh() {
  if [ "$mode" = tab ]; then
    exec "$herdr_bin" plugin pane open \
      --plugin herdr-tussh --entrypoint tussh \
      --placement tab --focus
  fi
  exec "$herdr_bin" plugin pane open \
    --plugin herdr-tussh --entrypoint tussh \
    --placement split --direction right --focus
}

command -v jq >/dev/null 2>&1 || open_tussh
panes="$("$herdr_bin" pane list 2>/dev/null)" || open_tussh
[ -n "$panes" ] || open_tussh

# Decide OPEN / "FOCUS <pane>" / "CLOSE <pane>" / "SWITCHTAB <tab>".
# The tussh pane is matched by its label. Ids must be flag-safe (never start
# with "-") before they reach an argv. The workspace is the prefix of an id
# ("w1:t2" -> "w1"); a tussh pane in another workspace is ignored rather than
# yanking the user there.
decision="$(printf '%s' "$panes" | jq -r --arg mode "$mode" '
  def safe: type == "string" and length > 0 and test("^[A-Za-z0-9_:.][A-Za-z0-9_:.-]*$");
  def ws: (.tab_id // .pane_id // "") | split(":") | if length > 1 and .[0] != "" then .[0] else null end;
  (.result.panes // []) as $panes
  | ($panes | map(select(.focused == true)) | first) as $focused
  | if $focused == null then "OPEN"
    else
      ($panes | map(select(.label == "tussh"))) as $ls
      | ($ls | map(select(.tab_id == $focused.tab_id)) | first) as $here
      | if $here != null then
          if (($here.pane_id // "") | safe | not) then "OPEN"
          elif $here.pane_id == $focused.pane_id then "CLOSE \($here.pane_id)"
          else "FOCUS \($here.pane_id)"
          end
        elif $mode == "tab" then
          ($focused | ws) as $fws
          | ($ls | map(select($fws != null and (ws) == $fws)) | first) as $other
          | if $other != null and (($other.tab_id // "") | safe) then "SWITCHTAB \($other.tab_id)"
            else "OPEN"
            end
        else "OPEN"
        end
    end' 2>/dev/null)" || decision="OPEN"

case "$decision" in
  "SWITCHTAB "*)
    "$herdr_bin" tab focus "${decision#SWITCHTAB }" && exit 0
    open_tussh
    ;;
  "FOCUS "*)
    pid="${decision#FOCUS }"
    # herdr has no "focus pane by id"; zooming a pane focuses it.
    "$herdr_bin" pane zoom "$pid" --on >/dev/null 2>&1 || true
    exec "$herdr_bin" pane zoom "$pid" --off
    ;;
  "CLOSE "*)
    exec "$herdr_bin" pane close "${decision#CLOSE }"
    ;;
  *)
    open_tussh
    ;;
esac
