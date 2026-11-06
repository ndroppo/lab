# Shared-project Git checks, sourced by verify.sh.

guest_git() {
  run command -v git
  [[ $OUT == /usr/local/bin/git ]] || { FINDING="git resolves to $OUT, not Lab's wrapper"; return 1; }
  run findmnt -T /mnt/lab-git -n -o FSTYPE,OPTIONS,TARGET
  read fs opts target <<< "$OUT"
  [[ $fs == virtiofs && $target == /mnt/lab-git && ,$opts, == *,ro,* ]] || { FINDING="no read-only git-store mount"; return 1; }
  run findmnt -T "$LAB_GIT_STORE" -n -o FSTYPE
  [[ $OUT != virtiofs && $OUT ]] || { FINDING="metadata copies are not guest-local"; return 1; }
  run stat -c %U "$LAB_GIT_STORE" /run/lab-git
  expected=$(echo -e "$LAB_AGENT\n$LAB_AGENT")
  [[ $OUT == "$expected" && -w $LAB_GIT_STORE && -w /run/lab-git ]] || { FINDING="metadata root or boot cache is not the agent's"; return 1; }
  FINDING="wrapper on PATH, read-only origin mounted, local metadata and boot cache writable"
}

git_identity() {
  run /usr/bin/git config --system --get user.name
  name=$OUT
  run /usr/bin/git config --system --get user.email
  FINDING="$name <$OUT>"
  [[ $name == "$LAB_AGENT" && $OUT == "$LAB_AGENT@localhost" ]]
}

check git "Git uses the wrapper, a mounted origin and agent-owned local metadata." guest_git
check identity "Guest commits use the agent's own name and localhost email." git_identity
