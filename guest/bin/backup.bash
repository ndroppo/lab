# Shared archive mechanics. Sourced as the agent, never root.
# Each owner sets STATE_SKIP (top-level names), STATE_EXCLUDE (tar patterns),
# and backup_check (the cold-state check immediately before publication).
# Symlinks are preserved, not followed. External targets need their own backup.

state_paths() {
  state_root=$1
  state_files=()
  local path name pattern skip
  for path in "$state_root"/* "$state_root"/.[!.]* "$state_root"/..?*; do
    [[ -e $path || -L $path ]] || continue
    name=${path##*/}
    skip=false
    for pattern in '.lab-restore*' "${STATE_SKIP[@]}"; do
      [[ $name == $pattern ]] && skip=true
    done
    $skip || state_files+=("$name")
  done
  return 0
}

state_save() (
  local root=$1 archive=$2 extra=${3:-} tmp empty pattern
  umask 077
  [[ ! -e $root/.lab-restore ]] || { echo "backup: finish the interrupted restore of $root first." >&2; exit 1; }
  state_paths "$root" || exit 1
  mkdir -p "${archive%/*}" || exit 1
  tmp=$(mktemp "${archive%/*}/.state.XXXXXX") || exit 1
  empty=$(mktemp -d) || exit 1
  trap 'rm -f "$tmp"; rm -rf "$empty"' EXIT
  mkdir "$empty/files" || exit 1
  tar -cf "$tmp" -C "$empty" files || exit 1
  local options=()
  for pattern in "${STATE_EXCLUDE[@]}"; do options+=(--exclude="$pattern"); done
  if (( ${#state_files[@]} )); then
    # Transform member and hardlink names, but never symlink targets.
    tar -rf "$tmp" "${options[@]}" --transform='flags=rh;s|^|files/|' \
      -C "$root" -- "${state_files[@]}" || exit 1
  fi
  [[ ! $extra ]] || tar -rf "$tmp" -C "$extra" . || exit 1
  tar -tf "$tmp" > /dev/null && backup_check && mv -f "$tmp" "$archive" || exit 1
)

# Called inside a subshell: the extraction stays private and its EXIT trap
# cleans up on both failures and success. Keep the archive until all owners'
# copy/merge steps succeed. A failed copy can retry, but never overwrite an
# unrelated existing installation.
state_open() {
  local root=$1 archive=$2
  state_paths "$root" || return 1
  if (( ${#state_files[@]} )) && [[ ! -e $root/.lab-restore ]]; then
    echo "restore: $root already has user state; refusing to overwrite it. Backup retained." >&2
    return 1
  fi
  mkdir -p "$root" || return 1
  STATE_STAGE=$(mktemp -d "$root/.lab-restore.XXXXXX") || return 1
  trap 'rm -rf "$STATE_STAGE"' EXIT
  tar -xf "$archive" -C "$STATE_STAGE" || return 1
  [[ -d $STATE_STAGE/files && ! -L $STATE_STAGE/files ]] || return 1
  : > "$root/.lab-restore" || return 1
  STATE_ROOT=$root STATE_ARCHIVE=$archive
}

state_finish() {
  local path files=()
  for path in "$STATE_STAGE/files"/* "$STATE_STAGE/files"/.[!.]* "$STATE_STAGE/files"/..?*; do
    [[ -e $path || -L $path ]] && files+=("$path")
  done
  if (( ${#files[@]} )); then cp -a -- "${files[@]}" "$STATE_ROOT/" || return 1; fi
  rm -f "$STATE_ROOT/.lab-restore" "$STATE_ARCHIVE"
}

# Shared user skills belong to neither harness. Base restores them before
# either harness is provisioned. This also runs in rooms without a harness.
skills_backup() (
  STATE_SKIP=() STATE_EXCLUDE=()
  backup_check() { return 0; }
  state_save "$HOME/.agents/skills" "$BACKUP/agents.tar"
)
skills_restore() (
  if [[ ! -f $BACKUP/agents.tar ]]; then
    [[ ! -e $HOME/.agents/skills/.lab-restore ]] || { echo "skills: interrupted restore has lost its archive." >&2; exit 1; }
    exit 0
  fi
  STATE_SKIP=() STATE_EXCLUDE=()
  if [[ ${1:-} == --boot ]]; then
    state_paths "$HOME/.agents/skills"
    [[ -e $state_root/.lab-restore || ${#state_files[@]} == 0 ]] || exit 0
  fi
  state_open "$HOME/.agents/skills" "$BACKUP/agents.tar" && state_finish
)
