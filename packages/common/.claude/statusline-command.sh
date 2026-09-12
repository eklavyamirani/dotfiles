#!/bin/bash
# Status line derived from the zsh PS1 in dev/.zshrc:
#   export PS1="|%F{green}%n@%m%f|%F{green}%~%f|"$'\n'" %# > "
# Renders: |user@host|cwd|model (effort)|5h:X% 7d:Y%|
input=$(cat)

user=$(whoami)
host=$(hostname -s)

cwd=$(echo "$input" | jq -r '.workspace.current_dir')
display_cwd="${cwd/#$HOME/~}"

model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort" ]; then
  model_info="${model} (${effort})"
else
  model_info="$model"
fi

five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
limits=""
[ -n "$five" ] && limits="5h:$(printf '%.0f' "$five")%"
if [ -n "$week" ]; then
  week_fmt="7d:$(printf '%.0f' "$week")%"
  limits="${limits:+$limits }${week_fmt}"
fi

line="\033[32m|${user}@${host}|${display_cwd}|${model_info}"
[ -n "$limits" ] && line="${line}|${limits}"
line="${line}|\033[0m"

printf "%b" "$line"
