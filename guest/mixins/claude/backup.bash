# Sourced as the agent by backup.sh or boot provisioning.
CLAUDE_BACKUP_DIR=$(dirname -- "${BASH_SOURCE[0]}")
. "$CLAUDE_BACKUP_DIR/../../bin/backup.bash" || return 1

claude_stopped() {
  if pgrep -u "$(id -u)" -x 'claude(-.*)?' > /dev/null; then
    echo "claude backup: stop Claude before backing up or restoring its state." >&2
    return 1
  fi
}

claude_state() {
  home=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  # Native default is ~/.claude.json; an explicit config directory puts it
  # inside that directory (confirmed against the installed Claude bundle).
  if [[ $CLAUDE_CONFIG_DIR ]]; then global=$home/.claude.json; else global=$HOME/.claude.json; fi
  STATE_SKIP=(projects '.claude.json*' '.config.json*' '.credentials*' cache downloads session-env sessions
    shell-snapshots backups '*.lock' '.last-*' 'remote-settings.json*' 'policy-limits.json*')
  STATE_EXCLUDE=()
}

backup() (
  claude_stopped || exit 1
  claude_state
  extra=$(mktemp -d) || exit 1
  trap 'rm -rf "$extra"' EXIT
  python3 "$CLAUDE_BACKUP_DIR/global.py" save "$global" "$extra/global.json" || exit 1
  backup_check() { claude_stopped; }
  state_save "$home" "$BACKUP/claude/state.tar" "$extra" || exit 1
  echo "claude: saved user files, global preferences and MCP/project choices."
)

restore() (
  claude_state
  archive=$BACKUP/claude/state.tar
  if [[ ! -f $archive ]]; then
    [[ ! -e $home/.lab-restore ]] || { echo "claude: interrupted restore has lost its archive." >&2; exit 1; }
    exit 0
  fi
  claude_stopped || exit 1
  if [[ ! -e $home/.lab-restore ]]; then
    python3 "$CLAUDE_BACKUP_DIR/global.py" check "$global"
    result=$?
    if (( result == 0 )); then
      echo "claude: global user settings exist; refusing to overwrite them. Backup retained." >&2
      exit 1
    fi
    (( result == 1 )) || exit "$result"
  fi
  state_open "$home" "$archive" || exit 1
  python3 "$CLAUDE_BACKUP_DIR/global.py" restore "$global" "$STATE_STAGE/global.json" && state_finish || exit 1
  echo "claude: restored user state; consumed its backup."
)

restore_on_boot() (
  BACKUP=${BACKUP:-/mnt/lab-state/backup}
  claude_state
  state_paths "$home"
  if [[ ! -e $home/.lab-restore ]]; then
    (( ${#state_files[@]} == 0 )) || exit 0
    python3 "$CLAUDE_BACKUP_DIR/global.py" check "$global"
    result=$?
    if (( result == 0 )); then exit 0; fi
    (( result == 1 )) || exit "$result"
  fi
  restore
)
