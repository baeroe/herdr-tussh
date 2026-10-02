# herdr-tussh

Run [tussh](https://github.com/baeroe/tussh) in a [herdr](https://herdr.dev) split pane or in its own tab. tussh is an SSH connection manager with access control for AI agents. When an agent is waiting for your approval and no tussh window is open, this plugin pops up the approval alerts. herdr-tussh works the same way as [herdr-lazydocker](https://github.com/sudoeren/herdr-lazydocker) and [herdr-lazysql](https://github.com/baeroe/herdr-lazysql).

| Action | Does |
|---|---|
| `open-tussh` | Toggles tussh in a split to the right: opens it, focuses it, or closes it when it is focused |
| `open-tussh-tab` | Toggles tussh in its own tab: opens it, switches to its tab, focuses it, or closes it when it is focused |
| `alerts` | Opens `tussh alerts --popup` as a popup. The popup closes by itself once every request it showed has been decided. |

You don't need to bind `alerts` to a key. tussh invokes it on its own (`herdr plugin action invoke herdr-tussh.alerts`) when an agent request needs approval and no tussh TUI is running. If herdr is not running, tussh only shows a macOS notification.

The tussh pane is found by its label (`tussh`). If `jq` is missing or `herdr pane list` fails, the actions simply open a new tussh pane.

The plugin starts `tussh` from `PATH`, falling back to `~/.local/bin/tussh`. The herdr server often runs without `~/.local/bin` on its `PATH`. To use a different binary, set `TUSSH_BIN`.

Connections, access levels and approvals all belong to tussh. The plugin only opens it.

## Requirements

| Tool | Why |
|---|---|
| `tussh` | the SSH manager (`make install` in the tussh repo, which puts it in `~/.local/bin`) |
| `jq` | toggle logic (without it, every invocation opens a new pane) |
| herdr 0.9.3+ | |

## Install

```sh
herdr plugin install baeroe/herdr-tussh
```

Add key bindings to `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "alt+h"
type = "plugin_action"
command = "herdr-tussh.open-tussh"
description = "tussh"

# optional: tussh in its own tab
[[keys.command]]
key = "alt+shift+h"
type = "plugin_action"
command = "herdr-tussh.open-tussh-tab"
description = "tussh tab"
```

Then run `herdr server reload-config`.

## Tests

```sh
bash tests/run-tests.sh        # toggle decisions, launcher and alerts action against a fake herdr; no herdr needed (runs in CI)
shellcheck scripts/*.sh tests/*.sh
```

## Credits

The toggle logic is adapted from [herdr-lazydocker](https://github.com/sudoeren/herdr-lazydocker) (MIT) by Eren Çakar, by way of herdr-lazysql.

## License

MIT, see [LICENSE](LICENSE).
