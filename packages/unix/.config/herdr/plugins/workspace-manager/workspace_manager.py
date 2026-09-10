#!/usr/bin/env python3
"""Interactive workspace manager for Herdr.

Runs as a popup pane and talks to the Herdr socket API directly, because
workspace reordering (workspace.move) has no CLI wrapper.

In-popup keys are configurable via keys.toml in the plugin config directory
(HERDR_PLUGIN_CONFIG_DIR). See DEFAULT_KEYS below for the defaults.
"""

import curses
import json
import os
import socket
import sys
import tomllib

DEFAULT_SOCKET = os.path.expanduser("~/.config/herdr/herdr.sock")
DEFAULT_CONFIG_DIR = os.path.expanduser(
    "~/.config/herdr/plugins/config/local.workspace-manager"
)

STATUS_ORDER = ["working", "blocked", "done", "idle", "unknown"]

# Action -> default key names. Order matters: when two actions claim the same
# key, the one listed first here keeps it.
DEFAULT_KEYS = {
    "quit": ["q", "esc"],
    "cursor_down": ["j", "down"],
    "cursor_up": ["k", "up"],
    "cursor_top": ["g"],
    "cursor_bottom": ["G"],
    "move_down": ["J"],
    "move_up": ["K"],
    "rename": ["r"],
    "filter": ["/"],
    "focus": ["enter"],
}

SPECIAL_KEYS = {
    "enter": {10, 13, curses.KEY_ENTER},
    "return": {10, 13, curses.KEY_ENTER},
    "esc": {27},
    "escape": {27},
    "space": {32},
    "tab": {9},
    "up": {curses.KEY_UP},
    "down": {curses.KEY_DOWN},
    "left": {curses.KEY_LEFT},
    "right": {curses.KEY_RIGHT},
    "home": {curses.KEY_HOME},
    "end": {curses.KEY_END},
    "pgup": {curses.KEY_PPAGE},
    "pageup": {curses.KEY_PPAGE},
    "pgdn": {curses.KEY_NPAGE},
    "pagedown": {curses.KEY_NPAGE},
    "backspace": {curses.KEY_BACKSPACE, 127, 8},
}


class HerdrError(Exception):
    pass


class HerdrClient:
    """Newline-delimited JSON over the Herdr unix socket, one request per call."""

    def __init__(self, socket_path=None):
        self.socket_path = socket_path or os.environ.get("HERDR_SOCKET_PATH") or DEFAULT_SOCKET
        self._seq = 0

    def call(self, method, params=None):
        self._seq += 1
        request = {"id": f"wsm{self._seq}", "method": method, "params": params or {}}
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(5.0)
            sock.connect(self.socket_path)
        except OSError as exc:
            raise HerdrError(f"cannot reach herdr at {self.socket_path}: {exc}") from exc

        try:
            sock.sendall((json.dumps(request) + "\n").encode())
            buf = b""
            while b"\n" not in buf:
                chunk = sock.recv(65536)
                if not chunk:
                    raise HerdrError(f"herdr closed the connection during {method}")
                buf += chunk
        except socket.timeout as exc:
            raise HerdrError(f"timed out waiting for {method}") from exc
        finally:
            sock.close()

        response = json.loads(buf.split(b"\n", 1)[0])
        if "error" in response:
            error = response["error"]
            message = error.get("message") if isinstance(error, dict) else str(error)
            raise HerdrError(f"{method} failed: {message}")
        return response.get("result", {})

    def list_workspaces(self):
        return self.call("workspace.list").get("workspaces", [])

    def move_workspace(self, workspace_id, insert_index):
        result = self.call(
            "workspace.move", {"workspace_id": workspace_id, "insert_index": insert_index}
        )
        return result.get("workspaces", [])

    def rename_workspace(self, workspace_id, label):
        return self.call("workspace.rename", {"workspace_id": workspace_id, "label": label})

    def focus_workspace(self, workspace_id):
        return self.call("workspace.focus", {"workspace_id": workspace_id})


def insert_index_for(current_index, target_index):
    """Translate a desired final position into herdr's pre-move insert_index.

    workspace.move interprets insert_index against the list *before* the move,
    inserting the workspace ahead of whatever currently sits at that index. So
    moving an item downward has to account for its own removal shifting the
    tail left by one; moving upward does not.
    """
    if target_index > current_index:
        return target_index + 1
    return target_index


def resolve_key(name):
    """Map a key name to the curses codes it can arrive as, or None if unknown."""
    if not isinstance(name, str) or not name:
        return None
    if len(name) == 1:
        return {ord(name)}
    lowered = name.lower()
    if lowered in SPECIAL_KEYS:
        return set(SPECIAL_KEYS[lowered])
    if lowered.startswith("ctrl+") and len(lowered) == 6:
        letter = lowered[5]
        if "a" <= letter <= "z":
            return {ord(letter) - 96}
    return None


def load_keymap(config_dir=None):
    """Build {action: {"names": [...], "codes": {...}}} plus a list of warnings.

    Reads keys.toml from the plugin config dir when present; every action not
    named there keeps its default. Returns defaults unchanged on a parse error.
    """
    warnings = []
    config_dir = config_dir or os.environ.get("HERDR_PLUGIN_CONFIG_DIR") or DEFAULT_CONFIG_DIR
    path = os.path.join(config_dir, "keys.toml")

    overrides = {}
    if os.path.isfile(path):
        try:
            with open(path, "rb") as handle:
                overrides = tomllib.load(handle)
        except (OSError, tomllib.TOMLDecodeError) as exc:
            warnings.append(f"keys.toml ignored ({exc}); using defaults")
            overrides = {}

    for action in overrides:
        if action not in DEFAULT_KEYS:
            warnings.append(f"unknown action '{action}' in keys.toml")

    keymap = {}
    claimed = {}
    for action, default_names in DEFAULT_KEYS.items():
        raw = overrides.get(action, default_names)
        if isinstance(raw, str):
            raw = [raw]
        if not isinstance(raw, list):
            warnings.append(f"'{action}' must be a string or list; using default")
            raw = default_names

        names, codes = [], set()
        for name in raw:
            resolved = resolve_key(name)
            if resolved is None:
                warnings.append(f"unknown key '{name}' for {action}")
                continue
            taken = resolved & claimed.keys()
            if taken:
                owner = claimed[next(iter(taken))]
                warnings.append(f"'{name}' already bound to {owner}; ignored for {action}")
                continue
            for code in resolved:
                claimed[code] = action
            names.append(name)
            codes |= resolved
        keymap[action] = {"names": names, "codes": codes}

    return keymap, warnings


def status_label(workspace):
    status = workspace.get("agent_status") or "unknown"
    return status if status in STATUS_ORDER else "unknown"


class WorkspaceManager:
    def __init__(self, stdscr, client, keymap=None, warnings=None):
        self.stdscr = stdscr
        self.client = client
        self.keymap = keymap or load_keymap()[0]
        self.warnings = warnings or []
        self.action_for = {}
        for action, spec in self.keymap.items():
            for code in spec["codes"]:
                self.action_for[code] = action
        self.workspaces = []
        self.cursor = 0
        self.filter_text = ""
        self.message = ""
        self.colors = {}

    # ---------- data ----------

    def reload(self, workspaces=None):
        self.workspaces = workspaces if workspaces is not None else self.client.list_workspaces()
        self.clamp_cursor()

    def visible(self):
        if not self.filter_text:
            return list(self.workspaces)
        needle = self.filter_text.lower()
        return [w for w in self.workspaces if needle in w.get("label", "").lower()]

    def clamp_cursor(self):
        count = len(self.visible())
        if count == 0:
            self.cursor = 0
        else:
            self.cursor = max(0, min(self.cursor, count - 1))

    def selected(self):
        rows = self.visible()
        if not rows:
            return None
        return rows[self.cursor]

    def key_hint(self, action):
        names = self.keymap.get(action, {}).get("names") or []
        return names[0] if names else "-"

    # ---------- actions ----------

    def move_selected(self, delta):
        if self.filter_text:
            self.message = f"clear the filter ({self.key_hint('quit')} in filter) before reordering"
            return
        workspace = self.selected()
        if workspace is None:
            return
        current = self.cursor
        target = current + delta
        if target < 0 or target >= len(self.workspaces):
            return
        ordered = self.client.move_workspace(
            workspace["workspace_id"], insert_index_for(current, target)
        )
        self.reload(ordered or None)
        self.cursor = target
        self.message = f"moved {workspace.get('label', '')}"

    def rename_selected(self):
        workspace = self.selected()
        if workspace is None:
            return
        current = workspace.get("label", "")
        new_label = self.prompt("rename: ", current)
        if new_label is None:
            self.message = "rename cancelled"
            return
        new_label = new_label.strip()
        if not new_label or new_label == current:
            self.message = "rename cancelled"
            return
        self.client.rename_workspace(workspace["workspace_id"], new_label)
        self.reload()
        self.message = f"renamed to {new_label}"

    def focus_and_exit(self, workspace):
        if workspace is None:
            return False
        self.client.focus_workspace(workspace["workspace_id"])
        return True

    def focus_by_number(self, number):
        for workspace in self.workspaces:
            if workspace.get("number") == number:
                return self.focus_and_exit(workspace)
        self.message = f"no workspace {number}"
        return False

    # ---------- rendering ----------

    def setup_colors(self):
        if not curses.has_colors():
            return
        curses.start_color()
        try:
            curses.use_default_colors()
        except curses.error:
            pass
        pairs = {
            "working": curses.COLOR_YELLOW,
            "blocked": curses.COLOR_RED,
            "done": curses.COLOR_GREEN,
            "idle": curses.COLOR_CYAN,
            "unknown": curses.COLOR_WHITE,
            "accent": curses.COLOR_MAGENTA,
        }
        for index, (name, color) in enumerate(pairs.items(), start=1):
            try:
                curses.init_pair(index, color, -1)
                self.colors[name] = curses.color_pair(index)
            except curses.error:
                self.colors[name] = curses.A_NORMAL

    def color(self, name, fallback=curses.A_NORMAL):
        return self.colors.get(name, fallback)

    def addstr(self, y, x, text, attr=curses.A_NORMAL):
        height, width = self.stdscr.getmaxyx()
        if y < 0 or y >= height or x >= width:
            return
        text = text[: max(0, width - x - 1)]
        if not text:
            return
        try:
            self.stdscr.addstr(y, x, text, attr)
        except curses.error:
            pass

    def hint_line(self):
        return (
            f"{self.key_hint('cursor_down')}/{self.key_hint('cursor_up')} move · "
            f"{self.key_hint('move_down')}/{self.key_hint('move_up')} reorder · "
            f"{self.key_hint('rename')} rename · {self.key_hint('focus')} go · "
            f"1-9 jump · {self.key_hint('filter')} filter · {self.key_hint('quit')} quit"
        )

    def draw(self):
        self.stdscr.erase()
        height, width = self.stdscr.getmaxyx()
        rows = self.visible()

        header = " Workspaces "
        if self.filter_text:
            header += f"· filter: {self.filter_text} "
        self.addstr(0, 0, header.ljust(max(0, width - 1)), curses.A_REVERSE | curses.A_BOLD)

        list_top = 2
        list_height = max(0, height - list_top - 3)
        offset = 0
        if rows and list_height and self.cursor >= list_height:
            offset = self.cursor - list_height + 1

        if not rows:
            empty = "no matching workspaces" if self.filter_text else "no workspaces"
            self.addstr(list_top, 2, empty, curses.A_DIM)

        for row_index, workspace in enumerate(rows[offset : offset + list_height]):
            actual = row_index + offset
            y = list_top + row_index
            selected = actual == self.cursor
            base = curses.A_REVERSE if selected else curses.A_NORMAL

            number = workspace.get("number", "?")
            label = workspace.get("label", "")
            status = status_label(workspace)
            focused = workspace.get("focused", False)
            panes = workspace.get("pane_count", 0)
            tabs = workspace.get("tab_count", 0)

            marker = "▸" if selected else " "
            focus_mark = "•" if focused else " "
            left = f"{marker} {focus_mark} {number}  {label}"
            right = f"{status}   {tabs}t {panes}p "

            self.addstr(y, 0, left.ljust(max(0, width - 1)), base)
            right_x = max(0, width - len(right) - 1)
            if right_x > len(left) + 2:
                attr = base if selected else self.color(status)
                self.addstr(y, right_x, right, attr)

        footer_y = height - 2
        self.addstr(footer_y, 0, self.hint_line()[: max(0, width - 1)], curses.A_DIM)
        if self.message:
            self.addstr(footer_y + 1, 0, self.message[: max(0, width - 1)], self.color("accent"))

        self.stdscr.refresh()

    # ---------- input ----------

    def prompt(self, label, initial=""):
        """Inline line editor. Returns the text, or None if cancelled.

        Text entry always uses enter/esc/backspace; those are not remappable.
        """
        text = initial
        height, width = self.stdscr.getmaxyx()
        y = height - 1
        curses.curs_set(1)
        try:
            while True:
                self.stdscr.move(y, 0)
                self.stdscr.clrtoeol()
                self.addstr(y, 0, f"{label}{text}", curses.A_BOLD)
                self.stdscr.move(y, min(len(label) + len(text), max(0, width - 1)))
                self.stdscr.refresh()

                key = self.stdscr.getch()
                if key == 27:  # esc
                    return None
                if key in (10, 13, curses.KEY_ENTER):
                    return text
                if key in (curses.KEY_BACKSPACE, 127, 8):
                    text = text[:-1]
                    continue
                if key == curses.KEY_RESIZE:
                    height, width = self.stdscr.getmaxyx()
                    y = height - 1
                    continue
                if 32 <= key <= 126:
                    text += chr(key)
        finally:
            curses.curs_set(0)

    def filter_prompt(self):
        text = self.filter_text
        height, width = self.stdscr.getmaxyx()
        curses.curs_set(1)
        try:
            while True:
                self.filter_text = text
                self.clamp_cursor()
                self.draw()
                y = height - 1
                self.addstr(y, 0, f"/{text}", curses.A_BOLD)
                self.stdscr.move(y, min(1 + len(text), max(0, width - 1)))
                self.stdscr.refresh()

                key = self.stdscr.getch()
                if key == 27:  # esc clears the filter
                    self.filter_text = ""
                    self.clamp_cursor()
                    return
                if key in (10, 13, curses.KEY_ENTER):
                    return
                if key in (curses.KEY_BACKSPACE, 127, 8):
                    text = text[:-1]
                    continue
                if key == curses.KEY_RESIZE:
                    height, width = self.stdscr.getmaxyx()
                    continue
                if 32 <= key <= 126:
                    text += chr(key)
        finally:
            curses.curs_set(0)

    def run(self):
        curses.curs_set(0)
        self.setup_colors()
        self.reload()
        if self.warnings:
            self.message = self.warnings[0]
            if len(self.warnings) > 1:
                self.message += f" (+{len(self.warnings) - 1} more)"

        while True:
            self.draw()
            key = self.stdscr.getch()
            self.message = ""

            if key == curses.KEY_RESIZE:
                continue

            action = self.action_for.get(key)

            if action == "quit":
                return
            elif action == "cursor_down":
                if self.visible():
                    self.cursor = min(self.cursor + 1, len(self.visible()) - 1)
            elif action == "cursor_up":
                self.cursor = max(self.cursor - 1, 0)
            elif action == "cursor_top":
                self.cursor = 0
            elif action == "cursor_bottom":
                self.cursor = max(0, len(self.visible()) - 1)
            elif action == "move_down":
                self.move_selected(1)
            elif action == "move_up":
                self.move_selected(-1)
            elif action == "rename":
                self.rename_selected()
            elif action == "filter":
                self.filter_prompt()
            elif action == "focus":
                if self.focus_and_exit(self.selected()):
                    return
            elif action is None and ord("1") <= key <= ord("9"):
                if self.focus_by_number(key - ord("0")):
                    return


def main():
    client = HerdrClient()
    keymap, warnings = load_keymap()

    if "--list" in sys.argv:
        for workspace in client.list_workspaces():
            print(
                f"{workspace.get('number')}  {workspace.get('workspace_id')}  "
                f"{workspace.get('label')}  {status_label(workspace)}"
            )
        return 0

    if "--check-keys" in sys.argv:
        for action, spec in keymap.items():
            print(f"{action:14} {', '.join(spec['names']) or '(unbound)'}")
        for warning in warnings:
            print(f"warning: {warning}", file=sys.stderr)
        return 1 if warnings else 0

    try:
        client.list_workspaces()
    except HerdrError as exc:
        print(f"workspace-manager: {exc}", file=sys.stderr)
        return 1

    def run(stdscr):
        WorkspaceManager(stdscr, client, keymap, warnings).run()

    try:
        curses.wrapper(run)
    except HerdrError as exc:
        print(f"workspace-manager: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
