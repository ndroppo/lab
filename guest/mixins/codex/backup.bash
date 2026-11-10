# Sourced as the agent by backup.sh or this mixin's boot provisioning.
# BACKUP is the backup directory, normally /mnt/lab-state/backup.

codex_stopped() {
  if pgrep -u "$(id -u)" -x 'codex(-.*)?' > /dev/null; then
    echo "codex backup: stop Codex before backing up or restoring its index." >&2
    return 1
  fi
}

codex_paths() {
  home=${1:-${CODEX_HOME:-$HOME/.codex}}
  files=()
  for path in "$home"/sqlite "$home"/*.sqlite "$home"/*.sqlite-wal "$home"/*.sqlite-shm \
      "$home"/session_index.jsonl "$home"/history.jsonl; do
    [[ -e $path || -L $path ]] || continue
    [[ ! -L $path ]] || { echo "codex: index entry is a symlink: $path" >&2; return 1; }
    files+=("${path##*/}")
  done
  return 0
}

backup() (
  codex_stopped || exit 1
  codex_paths || exit 1
  [[ ! -f $home/.lab-index-restore ]] || { echo "codex: finish the interrupted restore before backing up." >&2; exit 1; }
  if (( ! ${#files[@]} )); then
    echo "codex: no local index; previous backup, if any, retained." >&2
    exit 0
  fi
  mkdir -p "$BACKUP/codex" || exit 1
  tmp=$(mktemp "$BACKUP/codex/.index.XXXXXX") || exit 1
  trap 'rm -f "$tmp"' EXIT
  tar -cf "$tmp" -C "$home" -- "${files[@]}" &&
    tar -tf "$tmp" > /dev/null && codex_stopped &&
    mv -f "$tmp" "$BACKUP/codex/index.tar" || exit 1
  echo "codex: saved index, SQLite files and journals (no credentials or rollouts)." >&2
)

restore() (
  archive=$BACKUP/codex/index.tar
  if [[ ! -f $archive ]]; then
    [[ ! -f ${CODEX_HOME:-$HOME/.codex}/.lab-index-restore ]] || {
      echo "codex: interrupted restore has lost its backup archive." >&2; exit 1;
    }
    echo "codex: no index backup." >&2
    exit 0
  fi
  codex_stopped || exit 1
  codex_paths || exit 1
  if (( ${#files[@]} )) && [[ ! -f $home/.lab-index-restore ]]; then
    echo "codex: local index exists; refusing to overwrite it. Backup retained." >&2
    exit 1
  fi
  mkdir -p "$home" || exit 1
  tmp=$(mktemp -d "$home/.index.XXXXXX") || exit 1
  trap 'rm -rf "$tmp"' EXIT
  tar -xf "$archive" -C "$tmp" || exit 1
  destination=$home
  codex_paths "$tmp" || exit 1
  (( ${#files[@]} )) || { echo "codex: archive has no index; backup retained." >&2; exit 1; }
  # A marker lets a failed first-boot copy retry instead of mistaking its
  # partial files for an existing user index. The archive stays until success.
  : > "$destination/.lab-index-restore" || exit 1
  for file in "${files[@]}"; do cp -a "$tmp/$file" "$destination/" || exit 1; done
  rm -f "$destination/.lab-index-restore" && rm -f "$archive" || exit 1
  echo "codex: restored index; consumed its backup." >&2
)

restore_on_boot() {
  BACKUP=/mnt/lab-state/backup
  codex_paths || return 1
  [[ -f $home/.lab-index-restore || ${#files[@]} == 0 ]] || return 0
  restore
}
