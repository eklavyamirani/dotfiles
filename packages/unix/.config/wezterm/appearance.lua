-- Appearance: transparency, font, and the retro tab bar.
--
-- Deployed by stow to ~/.config/wezterm/appearance.lua and pulled in by
-- wezterm.lua. Split out from the entry point so the three concerns this
-- config exists for (look, agent-aware tab titles, tmux keys) stay
-- independently readable.

local wezterm = require 'wezterm'

local M = {}

-- Catppuccin Mocha, to match the Neovim config (external repo; see the
-- dotfiles README). WezTerm ships the scheme built in -- nothing to install.
M.scheme_name = 'Catppuccin Mocha'
M.scheme = wezterm.color.get_builtin_schemes()[M.scheme_name]

function M.apply(config)
  config.color_scheme = M.scheme_name

  -- Use Metal on macOS. The default OpenGL renderer cannot create an
  -- NSOpenGLPixelFormat on this macOS VM and exits before opening a window.
  if wezterm.target_triple:find('apple%-darwin') then
    config.front_end = 'WebGpu'
  end

  -- ---- Transparency -------------------------------------------------
  -- 0.88 is deliberately not lower: below ~0.8 the desktop starts
  -- competing with the text, and Catppuccin's low-contrast comment colour
  -- is the first thing to become unreadable. The macOS blur does the
  -- visual heavy lifting instead -- it frosts whatever is behind the
  -- window, so a busy desktop stays a texture rather than legible content.
  config.window_background_opacity = 0.88
  config.macos_window_background_blur = 30

  -- Dim inactive panes slightly, so the focused one reads as focused even
  -- through the transparency. Kept mild -- a hard dim plus 0.88 opacity
  -- compounds into genuinely hard-to-read background panes.
  config.inactive_pane_hsb = {
    saturation = 0.92,
    brightness = 0.78,
  }

  -- ---- Font ---------------------------------------------------------
  -- font-fira-code-nerd-font is the one cask declared in manifests/macos/Brewfile.
  -- The Nerd Font variant matters here: the tab-title glyphs in
  -- agent_status.lua and the Neovim statusline both draw from it.
  config.font = wezterm.font_with_fallback {
    'FiraCode Nerd Font',
    'Menlo', -- always present on macOS; keeps a fresh machine legible
  }
  config.font_size = 13.0

  -- ---- Window -------------------------------------------------------
  config.window_decorations = 'TITLE|RESIZE'
  config.window_padding = { left = 8, right = 8, top = 0, bottom = 6 }

  -- Default window size, in cells (the tab bar's row is added on top of
  -- these). Matches the size the window is normally dragged to, so a new
  -- window opens where the old one was rather than at WezTerm's 80x24.
  config.initial_cols = 138
  config.initial_rows = 39
  config.window_close_confirmation = 'NeverPrompt'
  config.scrollback_lines = 10000

  -- ---- Tab bar ------------------------------------------------------
  -- Retro (non-fancy) bar at the top: unlike the fancy bar it is drawn
  -- inside the terminal area, so the window transparency above actually
  -- applies to it.
  config.use_fancy_tab_bar = false
  config.tab_bar_at_bottom = false
  config.hide_tab_bar_if_only_one_tab = false
  config.tab_max_width = 32
  config.show_new_tab_button_in_tab_bar = false

  config.colors = {
    tab_bar = {
      background = 'rgba(0,0,0,0)',
      inactive_tab_edge = 'rgba(0,0,0,0)',
    },
  }

  -- Repaint the status area about once a second. This is what keeps the
  -- agent detection in the tab titles current: a pane's foreground process
  -- changing does not on its own redraw the tab bar, so without a timed
  -- repaint a tab could sit showing an agent that already exited.
  config.status_update_interval = 1000
end

return M
