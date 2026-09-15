-- Agent-aware tab titles.
--
-- Answers "which of my tabs has an agent running in it?" without switching
-- to each tab to look. It reads each pane's foreground process and
-- recognises the agent CLIs pinned in packages/common/.config/mise/config.toml.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. It does not distinguish an agent
-- that is working from one that has been blocked on a permission prompt
-- for ten minutes. That distinction is not observable from outside the
-- process -- the agent has to report it -- so showing it would mean an
-- adapter per agent, wired into each one's own hook mechanism: Claude
-- Code's settings.json, Codex's hooks.json, nothing at all for Copilot,
-- and a code change for pi. Four mechanisms to maintain for one glyph.
--
-- Process detection needs no cooperation from anything, so it covers
-- every agent equally, including ones not installed yet. That is the whole
-- design: one thing that always works over four that each work once.

local wezterm = require 'wezterm'
local appearance = require 'appearance'

local M = {}

local c = appearance.scheme
local TEXT = c.foreground
local DIM = c.brights[1] -- surface grey: the "nothing happening" colour
local ACTIVE = c.ansi[4] -- yellow: an agent holds this tab

-- Foreground process basename -> display name. Only the agents actually
-- pinned in mise, plus a couple likely to show up here; anything
-- unrecognised falls through to the pane's own title.
--
-- These resolve cleanly because every one of them is a native binary. An
-- agent installed as an npm package would appear as `node` instead, and
-- would need its wrapper name added here to be distinguishable.
local AGENT_PROCESSES = {
  claude = 'claude',
  codex = 'codex',
  copilot = 'copilot',
  pi = 'pi',
  aider = 'aider',
}

-- Field access on WezTerm's userdata can raise on versions where a field
-- does not exist, rather than returning nil. Every read of pane metadata
-- goes through here so a WezTerm upgrade (or downgrade) degrades the tab
-- title instead of breaking config loading outright.
local function try(fn, fallback)
  local ok, value = pcall(fn)
  if ok and value ~= nil then
    return value
  end
  return fallback
end

local function basename(path)
  if not path or path == '' then
    return nil
  end
  return path:gsub('%.exe$', ''):match '([^/\\]+)$'
end

-- current_working_dir is a Url object on this WezTerm (it stopped being a
-- plain string in 20240127-113634). Handle both shapes so the config is
-- not pinned to one release. Takes the raw value rather than the pane,
-- because the GUI pane struct and the mux pane object expose it under
-- different names and the overlay below reads the mux one.
local function cwd_label(cwd)
  if not cwd then
    return nil
  end
  local path = type(cwd) == 'string' and cwd or try(function() return cwd.file_path end)
  if not path then
    return nil
  end
  path = path:gsub('/$', '')
  if path == os.getenv 'HOME' then
    return '~'
  end
  return basename(path)
end

local function cwd_name(pane)
  return cwd_label(try(function() return pane.current_working_dir end))
end

local function title_for(tab)
  local pane = tab.active_pane
  local process = basename(try(function() return pane.foreground_process_name end))
  local agent = process and AGENT_PROCESSES[process] or nil
  local cwd = cwd_name(pane)
  local cells = {}

  local function push(color, text)
    table.insert(cells, { Foreground = { Color = color } })
    table.insert(cells, { Text = text })
  end

  -- Tab index, tmux-style: 1-based, and the number you press after the
  -- leader to get here.
  push(tab.is_active and c.ansi[5] or DIM, string.format(' %d ', tab.tab_index + 1))

  if agent then
    push(ACTIVE, '● ')
    push(tab.is_active and TEXT or DIM, agent)
    if cwd then
      push(DIM, '  ' .. cwd)
    end
  else
    -- No agent: fall back to the working directory, then the pane's own
    -- title, which is whatever the shell or program set.
    local label = cwd or try(function() return pane.title end) or process or 'shell'
    push(tab.is_active and TEXT or DIM, label)
  end

  table.insert(cells, { Text = ' ' })
  return cells
end

-- Label for one entry of the vertical tab overlay (LEADER Tab, bound in
-- keybindings.lua). Same information as the tab title above, but built
-- from the *mux* API: the overlay enumerates tabs via
-- window:mux_window():tabs_with_info(), which yields mux objects with
-- method accessors, not the plain structs handed to format-tab-title.
-- Kept here so there is exactly one place that knows what an agent looks
-- like -- the process table and the colours above are the point of this
-- module, and a second copy in keybindings.lua would drift.
--
-- Columns are padded to fixed widths so the list reads as a table rather
-- than a ragged left edge; that alignment is most of what makes a
-- vertical list scannable at a glance.
function M.mux_tab_label(info)
  local pane = info.tab:active_pane()
  local process = basename(try(function() return pane:get_foreground_process_name() end))
  local agent = process and AGENT_PROCESSES[process] or nil
  local cwd = cwd_label(try(function() return pane:get_current_working_dir() end))
  local name = agent or cwd or try(function() return pane:get_title() end) or process or 'shell'

  return wezterm.format {
    -- The active tab is marked in the list itself: an InputSelector opens
    -- on the first entry, not on the current tab, so without a marker
    -- there is nothing saying where you already are.
    { Foreground = { Color = info.is_active and c.ansi[5] or DIM } },
    { Text = string.format('%s %d ', info.is_active and '▸' or ' ', info.index + 1) },
    { Foreground = { Color = agent and ACTIVE or DIM } },
    { Text = agent and '● ' or '  ' },
    { Foreground = { Color = info.is_active and TEXT or DIM } },
    { Text = string.format('%-12s', name) },
    { Foreground = { Color = DIM } },
    { Text = agent and (cwd or '') or '' },
  }
end

function M.setup()
  wezterm.on('format-tab-title', function(tab)
    return title_for(tab)
  end)

  -- The workspace browser: every workspace, always visible, in the left
  -- status area.
  --
  -- This is the only place WezTerm can draw something persistently -- the
  -- status areas share the tab bar's row, and there is no docked sidebar
  -- or panel to put a browser in. So the browser is a strip rather than a
  -- list: each workspace is one chip, the active one inverted, numbered
  -- with the digit that switches to it (LEADER CTRL-<n>, bound in
  -- keybindings.lua).
  --
  -- tmux's `[session]` marker is subsumed by this -- the active chip says
  -- the same thing and also says what else exists, which the marker never
  -- did.
  --
  -- It also still earns its old keep by forcing the status area to
  -- repaint on a timer (see status_update_interval in appearance.lua),
  -- which is what keeps the agent detection above current: a pane's
  -- foreground process changing is not on its own an event that redraws
  -- the tab bar.
  wezterm.on('update-status', function(window)
    local active = window:active_workspace()
    local names = wezterm.mux.get_workspace_names()
    local cells = {}

    for i, name in ipairs(names) do
      local is_active = name == active
      -- Only the first nine are reachable by digit, so only those are
      -- numbered -- a number you cannot press is noise.
      local label = i <= 9 and string.format(' %d %s ', i, name) or (' ' .. name .. ' ')

      if is_active then
        -- Inverted rather than merely recoloured: at this size a fill is
        -- the only thing that survives a glance across a crowded bar.
        table.insert(cells, { Background = { Color = c.ansi[5] } })
        table.insert(cells, { Foreground = { Color = '#11111b' } })
      else
        table.insert(cells, { Background = { Color = '#181825' } })
        table.insert(cells, { Foreground = { Color = DIM } })
      end
      table.insert(cells, { Text = label })

      -- Hard reset between chips, so one chip's fill cannot bleed into
      -- the gap after it.
      table.insert(cells, { Background = { Color = '#11111b' } })
      table.insert(cells, { Text = ' ' })
    end

    window:set_left_status(wezterm.format(cells))
  end)
end

return M
