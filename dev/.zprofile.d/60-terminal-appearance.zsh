# Make this account's shell visually unmistakable in Terminal.app: switch the
# window to a dedicated "Claude-Dev" settings set (dark red background, amber
# accents) for the lifetime of this login shell, and change the window/tab
# title. Reverts automatically when the shell exits.
#
# Only does anything when running inside Apple's Terminal.app — harmless
# no-op in iTerm2/other terminals or non-interactive shells.

if [[ "$TERM_PROGRAM" == "Apple_Terminal" && -o interactive ]]; then

  _claude_terminal_profile="Claude-Dev"

  # Create the settings set once if it doesn't already exist. Colors are a
  # starting point only — feel free to edit them directly in Terminal >
  # Settings > Profiles > Claude-Dev; this block won't touch it again once
  # it exists.
  if ! osascript -e "tell application \"Terminal\" to exists settings set \"$_claude_terminal_profile\"" 2>/dev/null | grep -q true; then
    osascript > /dev/null 2>&1 << EOF
tell application "Terminal"
  make new settings set with properties {name:"$_claude_terminal_profile"}
  tell settings set "$_claude_terminal_profile"
    set background color to {4000, 0, 0}
    set normal text color to {60000, 60000, 60000}
    set bold text color to {65535, 55000, 0}
    set cursor color to {65535, 30000, 0}
  end tell
end tell
EOF
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
