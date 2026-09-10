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
-- not pinned to one release.
local function cwd_name(pane)
  local cwd = try(function() return pane.current_working_dir end)
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

function M.setup()
  wezterm.on('format-tab-title', function(tab)
    return title_for(tab)
  end)

  -- Stands in for tmux's `[session]` marker. It also earns its keep by
  -- forcing the status area to repaint on a timer (see
  -- status_update_interval in appearance.lua), which is what keeps the
  -- agent detection above current -- a pane's foreground process changing
  -- is not on its own an event that redraws the tab bar.
  wezterm.on('update-status', function(window)
    window:set_left_status(wezterm.format {
      { Foreground = { Color = c.ansi[5] } },
      { Text = ' [' .. window:active_workspace() .. '] ' },
    })
  end)
end

return M
