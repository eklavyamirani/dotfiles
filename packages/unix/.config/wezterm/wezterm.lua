-- WezTerm configuration for the isolated dev account.
--
-- Deployed by stow to ~/.config/wezterm/wezterm.lua, which is where
-- WezTerm looks after $WEZTERM_CONFIG_FILE and ~/.wezterm.lua. WezTerm
-- puts this file's directory on Lua's package.path, so the three modules
-- beside it are require-able by bare name.
--
--   appearance.lua    transparency, font, retro tab bar
--   agent_status.lua  agent name + state in each tab title
--   keybindings.lua   tmux vocabulary on a Ctrl-b leader
--
-- Reload is live: WezTerm watches these files and re-reads them on save
-- (LEADER r is bound to the repeatable resize mode, not to reload --
-- there is nothing to bind, since saving is enough).

local wezterm = require 'wezterm'

-- WezTerm only puts the *standard* config directory on package.path, not
-- the directory of whatever file it actually loaded. Without this line the
-- three requires below resolve only when this file is deployed to
-- ~/.config/wezterm -- and a `wezterm --config-file <repo path>` check,
-- the obvious way to validate a change before stowing it, fails to find
-- them and silently falls back to WezTerm's built-in defaults.
package.path = wezterm.config_dir .. '/?.lua;' .. package.path

local appearance = require 'appearance'
local agent_status = require 'agent_status'
local keybindings = require 'keybindings'

-- config_builder surfaces mistyped option names as errors in the WezTerm
-- debug overlay instead of silently ignoring them.
local config = wezterm.config_builder()

appearance.apply(config)
keybindings.apply(config)
agent_status.setup()

return config
