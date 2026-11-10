# Sourced as the agent. The metadata copies are guest-local; only bundles
# and their worktree paths go on state. Never write to the read-only origin.

git_environment() {
  while read -r name; do unset "$name"; done < <(/usr/bin/git -C / rev-parse --local-env-vars)
}

backup() (
  git_environment
  [[ $LAB_GIT_STORE && -d $LAB_GIT_STORE ]] || { echo "git: no guest metadata store."; exit 0; }
  tmp=$(mktemp -d "$BACKUP/.git.XXXXXX") || exit 1
  trap 'rm -rf "$tmp"' EXIT
  count=0
  find "$LAB_GIT_STORE" -type d -name objects -prune -o -type f -name HEAD -print0 > "$tmp/.repos" || exit 1
  while IFS= read -r -d '' head; do
    repo=${head%/HEAD}
    [[ -f $repo/config && -d $repo/objects ]] || continue
    branches=$(/usr/bin/git --git-dir="$repo" for-each-ref --format='%(refname)' refs/heads) || exit 1
    [[ $branches ]] || continue
    worktree=$(/usr/bin/git --git-dir="$repo" config --get core.worktree) || exit 1
    bundle=$tmp/${repo#"$LAB_GIT_STORE"/}.bundle
    mkdir -p "${bundle%/*}" &&
      /usr/bin/git --git-dir="$repo" bundle create "$bundle" --branches &&
      /usr/bin/git --git-dir="$repo" bundle verify "$bundle" &&
      printf '%s\0' "$worktree" > "$bundle.worktree" || exit 1
    ((count++))
  done < "$tmp/.repos"
  rm "$tmp/.repos" || exit 1
  if (( ! count )); then
    echo "git: no local branches; previous backup, if any, retained."
    exit 0
  fi
  old=$(mktemp -d "$BACKUP/.git-old.XXXXXX") && rmdir "$old" || exit 1
  if [[ -e $BACKUP/git ]]; then mv "$BACKUP/git" "$old" || exit 1; fi
  if ! mv "$tmp" "$BACKUP/git"; then
    [[ ! -d $old ]] || mv "$old" "$BACKUP/git"
    exit 1
  fi
  [[ ! -d $old ]] || rm -rf "$old"
  echo "git: saved every local branch in $count repo(s)."
)

restore() (
  git_environment
  [[ -d $BACKUP/git ]] || { echo "git: no bundle backup."; exit 0; }
  [[ $LAB_GIT_STORE && -d $LAB_GIT_STORE ]] || { echo "git: no guest metadata store." >&2; exit 1; }
  while IFS= read -r -d '' bundle; do
    relative=${bundle#"$BACKUP/git"/}; relative=${relative%.bundle}
    repo=$LAB_GIT_STORE/$relative
    IFS= read -r -d '' worktree < "$bundle.worktree" || exit 1
    IFS= read -r pointer < "$worktree/.git" || exit 1
    [[ $pointer == "gitdir: $repo" ]] || { echo "git: wrong or missing worktree for $bundle" >&2; exit 1; }
    heads=$(/usr/bin/git -C / bundle list-heads "$bundle") || exit 1
    if [[ -d $repo ]]; then
      # A rerun is harmless, but restoring must not overwrite later work.
      matches=1
      while read -r tip ref; do
        [[ $(/usr/bin/git --git-dir="$repo" rev-parse --verify --quiet "$ref") == "$tip" ]] || matches=""
      done <<< "$heads"
      if [[ $matches ]]; then echo "git: already restored: $worktree"; continue; fi
      # git status may already have initialized the fresh placeholder.
      # Accept that pristine copy, not later commits or staged user changes.
      refs=$(/usr/bin/git --git-dir="$repo" for-each-ref --format='%(refname)' refs/heads) || exit 1
      if [[ $refs != *$'\n'* && $refs &&
            $(/usr/bin/git --git-dir="$repo" rev-parse HEAD) == $(/usr/bin/git --git-dir="$repo" rev-parse origin/HEAD) ]] &&
          /usr/bin/git --git-dir="$repo" diff-index --cached --quiet HEAD; then :; else
        echo "git: $worktree has existing work; backup retained for manual fetch." >&2
        exit 1
      fi
    fi
    # Let the normal wrapper create the copy first. Updating its new local
    # refs and index never checks out or writes the shared working files.
    git -C "$worktree" rev-parse --git-dir > /dev/null &&
      /usr/bin/git --git-dir="$repo" fetch --atomic --update-head-ok "$bundle" '+refs/heads/*:refs/heads/*' &&
      /usr/bin/git --git-dir="$repo" read-tree HEAD || exit 1
    echo "git: restored branches without changing working files: $worktree"
  done < <(find "$BACKUP/git" -type f -name '*.bundle' -print0)
)
