# tussh in a split next to a shell (ctrl+b h in the demo config, alt+h in the README).
Output ".vhs/split.gif"
Source "docs/tapes/config.tape"

Hide
Type '"$HERDR_DEMO" herdr' Enter
Sleep 4s
Type "clear; ls; cat docker-compose.yml" Enter
Sleep 1s
Ctrl+B
Type "h"
Sleep 3s
Show
Sleep 300ms
Screenshot "docs/screenshots/split.png"
