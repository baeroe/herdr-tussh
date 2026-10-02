# The alerts action: pending agent requests in a popup (ctrl+b a in the demo config).
Output ".vhs/alerts.gif"
Source "docs/tapes/config.tape"

Hide
Type '"$HERDR_DEMO" herdr' Enter
Sleep 4s
Type "clear; ls" Enter
Sleep 1s
Ctrl+B
Type "a"
Sleep 3s
Show
Sleep 300ms
Screenshot "docs/screenshots/alerts.png"
