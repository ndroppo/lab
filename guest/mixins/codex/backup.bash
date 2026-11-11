# Sourced as the agent by backup.sh or boot provisioning.
. "$(dirname -- "${BASH_SOURCE[0]}")/../../bin/backup.bash" || return 1

codex_stopped() {
  if pgrep -u "$(id -u)" -x 'codex(-.*)?' > /dev/null; then
    echo "codex backup: stop Codex before backing up or restoring its state." >&2
    return 1
  fi
}

codex_state() {
  # MCP OAuth's file fallback is CODEX_HOME/.credentials.json too:
  # https://github.com/openai/codex/blob/main/codex-rs/rmcp-client/src/oauth.rs
  STATE_SKIP=(sessions 'auth.json*' '.credentials*' auth.lock tmp logs 'log' 'shell_snapshots' '.lab-index-restore' cache models_cache.json version.json installation_id '*.lock' thread-writer-locks)
  STATE_EXCLUDE=('skills/.system')
}

backup() (
  codex_stopped || exit 1
  home=${CODEX_HOME:-$HOME/.codex}
  [[ ! -e $home/.lab-index-restore ]] || { echo "codex: finish the index restore first." >&2; exit 1; }
  codex_state
  backup_check() { codex_stopped; }
  state_save "$home" "$BACKUP/codex/state.tar" || exit 1
  rm -f "$BACKUP/codex/index.tar" || exit 1
  echo "codex: saved user state, including configuration, skills and cold SQLite."
)

restore() (
  home=${CODEX_HOME:-$HOME/.codex}
  if [[ ! -f $BACKUP/codex/state.tar ]]; then
    [[ ! -e $home/.lab-restore ]] || { echo "codex: interrupted restore has lost its archive." >&2; exit 1; }
    restore_index
    exit $?
  fi
  codex_stopped || exit 1
  codex_state
  state_open "$home" "$BACKUP/codex/state.tar" && state_finish || exit 1
  echo "codex: restored user state; consumed its backup."
)

restore_on_boot() (
  BACKUP=${BACKUP:-/mnt/lab-state/backup}
  home=${CODEX_HOME:-$HOME/.codex}
  if [[ -f $BACKUP/codex/state.tar ]]; then
    codex_state
    state_paths "$home"
    [[ -e $home/.lab-restore || ${#state_files[@]} == 0 ]] || exit 0
  else
    codex_paths || exit 1
    [[ -e $home/.lab-restore || -f $home/.lab-index-restore || ${#files[@]} == 0 ]] || exit 0
  fi
  restore
)

# Compatibility reader for pre-full-state backups. These contain only the
# old index, never configuration or skills; it cannot recover absent data.
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

restore_index() (
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
