diskcheck() {
  local target="$HOME"
  local limit=15
  local path_set=0

  while (( $# )); do
    case "$1" in
      --limit)
        shift
        if (( $# == 0 )) || [[ "$1" != <-> ]]; then
          echo "--limit requires a positive integer." >&2
          return 2
        fi
        limit="$1"
        ;;
      --path)
        shift
        if (( $# == 0 )); then
          echo "--path requires a directory." >&2
          return 2
        fi
        target="$1"
        path_set=1
        ;;
      --help|-h)
        echo "Usage: diskcheck [limit] [path] [--limit N] [--path PATH]"
        return
        ;;
      -*)
        echo "Unknown option: $1" >&2
        return 2
        ;;
      <->)
        limit="$1"
        ;;
      *)
        if (( path_set )); then
          echo "Only one path may be specified." >&2
          return 2
        fi
        target="$1"
        path_set=1
        ;;
    esac
    shift
  done

  if (( limit < 1 )); then
    echo "Limit must be greater than zero." >&2
    return 2
  fi

  if [[ ! -d "$target" ]]; then
    echo "Directory not found: $target" >&2
    return 2
  fi

  # macOS reports the real user-data capacity for the synthesised
  # /System/Volumes/Data volume, not for /; on Linux the root filesystem is
  # the honest answer and that path does not exist at all.
  local storage_volume="/"
  local storage_label="Disk storage"
  if [[ "$OSTYPE" == darwin* ]]; then
    storage_volume="/System/Volumes/Data"
    storage_label="Mac storage"
  fi

  echo "$storage_label:"
  df -h "$storage_volume" | awk 'NR == 1 || NR == 2'

  echo
  echo "Largest folders in $target:"
  du -hd 1 "$target" 2>/dev/null | sort -hr | head -n "$limit"
}
