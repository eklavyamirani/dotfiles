# Make this account's shell visually unmistakable in Terminal.app: switch the
# window to a dedicated "Claude-Dev" settings set (dark red background, amber
# accents) for the lifetime of this login shell, and change the window/tab
# title. Reverts automatically when the shell exits.
#
# Only does anything when running inside Apple's Terminal.app — harmless
# no-op in iTerm2/other terminals or non-interactive shells.

if [[ "$TERM_PROGRAM" == "Apple_Terminal" && -o interactive ]]; then

  _claude_terminal_profile="Claude-Dev"
  _claude_terminal_profile_conf="$HOME/.config/terminal/claude-dev-profile.env"
  _claude_terminal_profile_file="$HOME/.config/terminal/Claude-Dev.terminal"

  # Create the settings set once if it doesn't already exist (this only
  # happens the first time Terminal.app launches after a full quit/restart --
  # the settings set only lives in Terminal's in-memory state and is never
  # written to ~/Library/Preferences/com.apple.Terminal.plist, so it doesn't
  # survive Terminal actually quitting).
  #
  # Prefer importing dev/.config/terminal/Claude-Dev.terminal if present --
  # a real Terminal.app profile export (Settings > Profiles > gear icon >
  # Export...), which captures font, size, colors, AND background
  # opacity/transparency losslessly as binary NSColor/NSFont archives.
  # Falls back to reconstructing colors/font/size from the plain-text
  # claude-dev-profile.env via AppleScript (loses opacity -- Terminal's
  # AppleScript dictionary has no scriptable opacity property at all) if no
  # .terminal export exists yet.
  #
  # Feel free to tweak everything directly in Terminal > Settings > Profiles
  # > Claude-Dev afterward — this block won't touch it again once it exists.
  # Run `claude-dev-export-terminal-profile` (env file, loses opacity) or
  # re-export via Settings > Profiles > gear icon > Export... (full fidelity,
  # overwrite dev/.config/terminal/Claude-Dev.terminal) to save tweaks back
  # to git.
  if ! osascript -e "tell application \"Terminal\" to exists settings set \"$_claude_terminal_profile\"" 2>/dev/null | grep -q true; then
    if [[ -f "$_claude_terminal_profile_file" ]]; then
      # `open` always creates a new frontmost window to do the import;
      # close it right away since it's not the shell that triggered this.
      open "$_claude_terminal_profile_file"
      sleep 1
      osascript -e 'tell application "Terminal" to if (count of windows) > 0 then close window 1' > /dev/null 2>&1
    else
      [[ -f "$_claude_terminal_profile_conf" ]] && source "$_claude_terminal_profile_conf"
      osascript > /dev/null 2>&1 << EOF
tell application "Terminal"
  make new settings set with properties {name:"$_claude_terminal_profile"}
  tell settings set "$_claude_terminal_profile"
    set background color to {${CLAUDE_TERM_BACKGROUND:-4000, 0, 0}}
    set normal text color to {${CLAUDE_TERM_NORMAL_TEXT:-60000, 60000, 60000}}
    set bold text color to {${CLAUDE_TERM_BOLD_TEXT:-65535, 55000, 0}}
    set cursor color to {${CLAUDE_TERM_CURSOR:-65535, 30000, 0}}
    set font to "${CLAUDE_TERM_FONT:-Menlo-Regular}"
  end tell
  -- "size" alone is AppleScript-ambiguous and errors from inside a nested
  -- "tell settings set" block (Terminal error -10006); "font size" is the
  -- real settable property name and works fine flat, outside the tell block.
  set font size of settings set "$_claude_terminal_profile" to ${CLAUDE_TERM_FONT_SIZE:-12}
end tell
EOF
    fi
  fi

  # Remember the window's current profile so we can restore it on exit
  # (falls back to "Basic" if it can't be determined).
  export _CLAUDE_PREV_TERMINAL_PROFILE="$(osascript -e 'tell application "Terminal" to get name of current settings of front window' 2>/dev/null)"
  [[ -z "$_CLAUDE_PREV_TERMINAL_PROFILE" ]] && _CLAUDE_PREV_TERMINAL_PROFILE="Basic"

  osascript -e "tell application \"Terminal\" to set current settings of front window to settings set \"$_claude_terminal_profile\"" > /dev/null 2>&1

  # Also change the window/tab title as a second, terminal-agnostic signal.
  printf '\033]0;\xe2\x9a\xa0 claude (dev) \xe2\x9a\xa0\007'

  # Restore the previous profile and title when this login shell exits
  # (covers both `exit` and closing the tab/window while still in this shell).
  _claude_restore_terminal_profile() {
    osascript -e "tell application \"Terminal\" to set current settings of front window to settings set \"$_CLAUDE_PREV_TERMINAL_PROFILE\"" > /dev/null 2>&1
    printf '\033]0;\007'
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook zshexit _claude_restore_terminal_profile

  unset _claude_terminal_profile
fi

# Re-export the live Claude-Dev settings set's colors back into the
# version-controlled config file, so manual tweaks made in Terminal >
# Settings > Profiles > Claude-Dev get captured by git/stow. Run this after
# tweaking, then commit + push from the dotfiles repo.
claude-dev-export-terminal-profile() {
  if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]]; then
    echo "Not running in Terminal.app; nothing to export." >&2
    return 1
  fi

  local conf="$HOME/.config/terminal/claude-dev-profile.env"
  if [[ ! -e "$conf" ]]; then
    echo "$conf not found (stow the dev package first)." >&2
    return 1
  fi

  local bg normal bold cursor font fontsize
  bg="$(osascript -e 'tell application "Terminal" to get background color of settings set "Claude-Dev"' 2>/dev/null)"
  if [[ -z "$bg" ]]; then
    echo "Claude-Dev settings set not found." >&2
    return 1
  fi
  normal="$(osascript -e 'tell application "Terminal" to get normal text color of settings set "Claude-Dev"' 2>/dev/null)"
  bold="$(osascript -e 'tell application "Terminal" to get bold text color of settings set "Claude-Dev"' 2>/dev/null)"
  cursor="$(osascript -e 'tell application "Terminal" to get cursor color of settings set "Claude-Dev"' 2>/dev/null)"
  font="$(osascript -e 'tell application "Terminal" to get font of settings set "Claude-Dev"' 2>/dev/null)"
  # "size" alone is AppleScript-ambiguous (get size of settings set errors),
  # so pull it out of the full properties record's text representation.
  local props
  props="$(osascript -e 'tell application "Terminal" to get properties of settings set "Claude-Dev"' 2>/dev/null)"
  fontsize="$(echo "$props" | sed -E 's/.*, size:([0-9]+),.*/\1/')"

  cat > "$conf" << EOF
# Color/font values for the dev account's "Claude-Dev" Terminal.app settings
# set. Colors are AppleScript RGB triples (0-65535 per channel), matching
# what \`tell application "Terminal" to get properties of settings set\` returns.
#
# NOTE: background opacity/transparency is NOT captured here -- Terminal.app's
# AppleScript dictionary has no scriptable opacity/alpha property (confirmed
# via \`sdef\`), so it can't be exported or replayed automatically. If you
# want the opacity to travel with this repo too, use Terminal's own native
# export instead: Settings > Profiles > (gear icon) > Export "Claude-Dev"...,
# save it as dev/.config/terminal/Claude-Dev.terminal, commit it, and import
# it via Settings > Profiles > (gear icon) > Import... on the new machine.
#
# Regenerate this file after tweaking colors/font in Terminal > Settings >
# Profiles > Claude-Dev by running: claude-dev-export-terminal-profile

CLAUDE_TERM_BACKGROUND="$bg"
CLAUDE_TERM_NORMAL_TEXT="$normal"
CLAUDE_TERM_BOLD_TEXT="$bold"
CLAUDE_TERM_CURSOR="$cursor"
CLAUDE_TERM_FONT="$font"
CLAUDE_TERM_FONT_SIZE="$fontsize"
EOF

  echo "Exported Claude-Dev colors/font to $conf"
  echo "Don't forget to: cd ~/repositories/dotfiles && git add -A && git commit && git push"
}
