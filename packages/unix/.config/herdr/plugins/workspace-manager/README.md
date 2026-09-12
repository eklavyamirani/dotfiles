# Workspace Manager

A Herdr plugin that adds workspace reordering, renaming, and direct jumping in a
popup — reordering in particular has no CLI wrapper, so this talks to the socket
API (`workspace.move`) directly.

## Keys

Open with `prefix+m`.

| Action | Default key |
| --- | --- |
| `cursor_down` / `cursor_up` | `j` / `k` (and arrows) |
| `cursor_top` / `cursor_bottom` | `g` / `G` |
| `move_down` / `move_up` | `J` / `K` — reorder the selected workspace |
| `rename` | `r` |
| `focus` | `enter` — go to selected workspace and close |
| `filter` | `/` — filter by name |
| `quit` | `q` / `esc` |
| (fixed) | `1`-`9` jump to that workspace and close |

Reordering is disabled while a filter is active, since positions shown would not
match positions in the real list.

## Configuring the in-popup keys

Edit `keys.toml` in the plugin config directory — `HERDR_PLUGIN_CONFIG_DIR`,
which is `~/.config/herdr/plugins/config/local.workspace-manager/`. Any action
you don't mention keeps its default:

```toml
cursor_down = ["n", "down"]
cursor_up   = ["p", "up"]
filter      = "ctrl+f"
```

Accepted key names: any single character, `ctrl+<letter>`, `enter`, `esc`,
`space`, `tab`, `backspace`, `up`, `down`, `left`, `right`, `home`, `end`,
`pgup`, `pgdn`. A key drives only one action; if two actions claim it, the one
declared first in `DEFAULT_KEYS` wins and the popup shows a warning on open. A
malformed `keys.toml` is ignored in favour of the defaults rather than failing
to start. The footer hint line reflects whatever is actually bound.

Verify a config without opening the popup:

```sh
python3 workspace_manager.py --check-keys   # exits non-zero if it warns
```

`1`-`9` stay bound to workspace jumping unless you bind those digits to an
action. Inside the rename and filter prompts, `enter`/`esc`/`backspace` always
mean confirm/cancel/delete and are not remappable.

## How reordering works

`workspace.move` takes `insert_index` in **pre-move** coordinates: the workspace
is inserted ahead of whatever currently sits at that index, and the item's own
removal then shifts the tail left by one. So moving down needs `target + 1` and
moving up needs `target`. That translation lives in `insert_index_for()`.

## Install

```sh
herdr plugin link ~/.config/herdr/plugins/workspace-manager
```

The keybinding lives in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+m"
type = "shell"
command = "\"$HERDR_BIN_PATH\" plugin pane open --plugin local.workspace-manager --entrypoint manager"
description = "workspace manager"
```

## Requirements

`python3` (stdlib only — `curses`, `socket`, `json`). macOS and Linux only,
because it uses a Unix domain socket; Windows named pipes are not handled.

## Debugging

`python3 workspace_manager.py --list` prints the workspace list without curses.
