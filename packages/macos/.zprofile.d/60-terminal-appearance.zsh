# Make Terminal.app visually distinct on this dev account: import the
# "Claude-Dev" profile (packages/macos/.config/terminal/Claude-Dev.terminal -- a real
# Terminal.app export capturing colors, font, size, and opacity) and set it
# as Terminal's default settings set for all new windows/tabs.
#
# Only runs once -- skipped once the settings set already exists. It only
# needs to re-run after a full Terminal.app quit/relaunch, since the
# settings set lives in Terminal's in-memory state and is never written to
# ~/Library/Preferences/com.apple.Terminal.plist.
#
# To update colors/font/size/opacity, tweak Claude-Dev in Terminal >
# Settings > Profiles directly, then re-export via the gear icon >
# Export... (overwrite packages/macos/.config/terminal/Claude-Dev.terminal) and commit.
#
# Only does anything when running inside Apple's Terminal.app — harmless
# no-op in iTerm2/other terminals, in non-interactive shells, and on Linux
# (where there is no Terminal.app and no osascript to drive it). COLORTERM
# below is set everywhere; only the profile import is gated.

export COLORTERM=truecolor

if [[ "$TERM_PROGRAM" == "Apple_Terminal" && -o interactive ]]; then
  _claude_terminal_profile="Claude-Dev"
  _claude_terminal_profile_file="$HOME/.config/terminal/Claude-Dev.terminal"

  if [[ -f "$_claude_terminal_profile_file" ]] && ! osascript -e "tell application \"Terminal\" to exists settings set \"$_claude_terminal_profile\"" 2>/dev/null | grep -q true; then
    # Importing always opens a new window -- close it right away since it's
    # not the shell that triggered this. Close by reference, not "window 1":
    # front-to-back ordering isn't guaranteed to have updated yet, and
    # "window 1" could be this very shell.
    osascript > /dev/null 2>&1 << EOF
tell application "Terminal"
  set newWin to (open POSIX file "$_claude_terminal_profile_file")
  close newWin
  set default settings to settings set "$_claude_terminal_profile"
end tell
EOF
  fi

  unset _claude_terminal_profile _claude_terminal_profile_file
fi
