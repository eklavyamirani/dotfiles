-- tmux-shaped keybindings, on a Ctrl-b leader.
--
-- The mapping between the two vocabularies:
--
--   tmux session  ->  WezTerm workspace
--   tmux window   ->  WezTerm tab
--   tmux pane     ->  WezTerm pane
--
-- Ctrl-b is the real tmux prefix, chosen deliberately: WezTerm replaces
-- tmux locally on this account (tmux stays pinned in mise for SSH), so
-- there is nothing inside a pane competing for the prefix. The one cost
-- is that Ctrl-b no longer reaches the shell as readline's
-- backward-char -- `LEADER Ctrl-b` sends a literal one, the same escape
-- hatch tmux itself provides.

local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

-- tmux's prefix has no timeout. WezTerm requires one, so it is set long
-- enough that it never expires mid-thought.
M.leader = { key = 'b', mods = 'CTRL', timeout_milliseconds = 2000 }

function M.apply(config)
  config.leader = M.leader

  local keys = {
    -- ---- prefix escape hatch ---------------------------------------
    -- LEADER Ctrl-b -> a literal Ctrl-b, exactly like tmux's send-prefix.
    { key = 'b', mods = 'LEADER|CTRL', action = act.SendKey { key = 'b', mods = 'CTRL' } },

    -- ---- panes (tmux panes) ----------------------------------------
    -- % and " are the tmux bindings; | and - are the same actions on
    -- unshifted keys, which is what most people reach for in practice.
    { key = '%', mods = 'LEADER|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
    { key = '|', mods = 'LEADER|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
    { key = '"', mods = 'LEADER|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
    { key = '-', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

    { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = true } },
    { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },
    { key = 'o', mods = 'LEADER', action = act.ActivatePaneDirection 'Next' },
    { key = 'q', mods = 'LEADER', action = act.PaneSelect { alphabet = '123456789' } },
    { key = ' ', mods = 'LEADER', action = act.RotatePanes 'Clockwise' },
    { key = '{', mods = 'LEADER|SHIFT', action = act.RotatePanes 'CounterClockwise' },
    { key = '}', mods = 'LEADER|SHIFT', action = act.RotatePanes 'Clockwise' },

    -- Directional movement: both vim keys and arrows, as tmux offers.
    { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
    { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
    { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
    { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
    { key = 'LeftArrow', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
    { key = 'DownArrow', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
    { key = 'UpArrow', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
    { key = 'RightArrow', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },

    -- One-off resize nudges; LEADER r opens the repeatable mode below.
    { key = 'LeftArrow', mods = 'LEADER|CTRL', action = act.AdjustPaneSize { 'Left', 5 } },
    { key = 'DownArrow', mods = 'LEADER|CTRL', action = act.AdjustPaneSize { 'Down', 5 } },
    { key = 'UpArrow', mods = 'LEADER|CTRL', action = act.AdjustPaneSize { 'Up', 5 } },
    { key = 'RightArrow', mods = 'LEADER|CTRL', action = act.AdjustPaneSize { 'Right', 5 } },
    {
      key = 'r',
      mods = 'LEADER',
      action = act.ActivateKeyTable { name = 'resize_pane', one_shot = false, timeout_milliseconds = 3000 },
    },

    -- ---- tabs (tmux windows) ---------------------------------------
    { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },
    { key = '&', mods = 'LEADER|SHIFT', action = act.CloseCurrentTab { confirm = true } },
    { key = 'n', mods = 'LEADER', action = act.ActivateTabRelative(1) },
    { key = 'p', mods = 'LEADER', action = act.ActivateTabRelative(-1) },
    { key = 'w', mods = 'LEADER', action = act.ShowTabNavigator },
    {
      key = ',',
      mods = 'LEADER',
      action = act.PromptInputLine {
        description = 'Rename tab',
        action = wezterm.action_callback(function(window, _, line)
          if line and line ~= '' then
            window:active_tab():set_title(line)
          end
        end),
      },
    },

    -- ---- workspaces (tmux sessions) --------------------------------
    -- LEADER s is tmux's session chooser; the fuzzy launcher is the
    -- closest equivalent and filters as you type.
    { key = 's', mods = 'LEADER', action = act.ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' } },
    { key = '(', mods = 'LEADER|SHIFT', action = act.SwitchWorkspaceRelative(-1) },
    { key = ')', mods = 'LEADER|SHIFT', action = act.SwitchWorkspaceRelative(1) },
    {
      -- New named workspace. SwitchToWorkspace creates on demand, so this
      -- is both "new session" and "attach to session" in one binding.
      key = 'C',
      mods = 'LEADER|SHIFT',
      action = act.PromptInputLine {
        description = 'New workspace name',
        action = wezterm.action_callback(function(window, pane, line)
          if line and line ~= '' then
            window:perform_action(act.SwitchToWorkspace { name = line }, pane)
          end
        end),
      },
    },
    {
      key = '$',
      mods = 'LEADER|SHIFT',
      action = act.PromptInputLine {
        description = 'Rename workspace',
        action = wezterm.action_callback(function(_, _, line)
          if line and line ~= '' then
            wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
          end
        end),
      },
    },

    -- ---- copy mode / misc ------------------------------------------
    { key = '[', mods = 'LEADER', action = act.ActivateCopyMode },
    { key = ']', mods = 'LEADER', action = act.PasteFrom 'Clipboard' },
    { key = ':', mods = 'LEADER|SHIFT', action = act.ActivateCommandPalette },
    { key = '?', mods = 'LEADER|SHIFT', action = act.ShowLauncherArgs { flags = 'FUZZY|KEY_ASSIGNMENTS' } },
    -- tmux's `d` detaches the client and leaves the session running. A
    -- local WezTerm domain cannot be detached from -- DetachDomain only
    -- means something for multiplexer/SSH domains, and errors on this one
    -- -- so `d` is mapped to the honest local equivalent: put the window
    -- away, leave every pane running.
    { key = 'd', mods = 'LEADER', action = act.HideApplication },
  }

  -- LEADER 1..9 jump to a tab, LEADER 0 to the tenth -- tmux's numbering,
  -- and the numbers shown at the left of each tab title.
  for i = 1, 9 do
    table.insert(keys, { key = tostring(i), mods = 'LEADER', action = act.ActivateTab(i - 1) })
  end
  table.insert(keys, { key = '0', mods = 'LEADER', action = act.ActivateTab(9) })

  config.keys = keys

  config.key_tables = {
    -- Repeatable resize, so holding the direction works like tmux's
    -- repeatable prefix bindings. Escape or Enter leaves.
    resize_pane = {
      { key = 'h', action = act.AdjustPaneSize { 'Left', 3 } },
      { key = 'j', action = act.AdjustPaneSize { 'Down', 3 } },
      { key = 'k', action = act.AdjustPaneSize { 'Up', 3 } },
      { key = 'l', action = act.AdjustPaneSize { 'Right', 3 } },
      { key = 'LeftArrow', action = act.AdjustPaneSize { 'Left', 3 } },
      { key = 'DownArrow', action = act.AdjustPaneSize { 'Down', 3 } },
      { key = 'UpArrow', action = act.AdjustPaneSize { 'Up', 3 } },
      { key = 'RightArrow', action = act.AdjustPaneSize { 'Right', 3 } },
      { key = 'Escape', action = 'PopKeyTable' },
      { key = 'Enter', action = 'PopKeyTable' },
    },
  }
end

return M
