#!/bin/bash
# verify.sh: prove the room is what it claims to be.
#
# Run inside the guest, as the agent user. Needs no privilege and changes
# nothing. Prints one line per check - its verdict, its label, and what its
# test found - a line counting the mounts, and a closing tally naming any
# failures. The claims and the
# evidence go to ~/.lab/verify.log, overwritten each run: each check's
# claim, then every command it ran, with its full output and exit status.
# Exits nonzero if any check failed.
#
# Nothing is hard-coded: the agent's name and mixins come from
# /etc/lab.env; mounts come from the guest's own mount table. Walls that
# rest on host facts - what was mounted, and from where - lab checks on the
# host; this checks what the guest can observe itself.

. /etc/lab.env || { echo "This instance was not built by lab, or base provisioning did not run." >&2; exit 1; }

LOG=~/.lab/verify.log
# Green and red marks on a terminal; plain marks when captured to a file.
if [[ -t 1 ]]; then pass=$'\e[32m✓\e[0m' fail=$'\e[31m✗\e[0m'; else pass=✓ fail=✗; fi
n=0
passed=0
failed=""

mkdir -p ~/.lab
{
  echo -e "verify.sh, $(date)\n"
  cat /etc/lab.env
} > "$LOG"

# run <command>...: runs it, logging the command, its full output, and its
# exit status; leaves the output in OUT and returns the status.
run() {
  OUT=$("$@" 2>&1)
  rc=$?
  {
    echo "\$ $*"
    [[ $OUT ]] && echo "$OUT"
    echo "(exit $rc)"
  } >> "$LOG"
  return "$rc"
}

# fails <command>...: passes when the command fails, finding the reason it
# gave - the last part of its first line, as in "sudo: a password is required".
fails() {
  if run "$@"; then
    FINDING=allowed
    return 1
  fi
  line=${OUT%%$'\n'*}
  FINDING="refused: ${line##*: }"
}

# check <label> <claim> <test>...: runs the test, its own output to the log
# under the claim, and prints the verdict with what the test found. Every
# test says what it found by setting FINDING.
check() {
  label=$1
  claim=$2
  shift 2
  FINDING=""
  ((n++))
  echo -e "\n$label: $claim" >> "$LOG"
  if "$@" >> "$LOG" 2>&1; then
    echo "✓ $FINDING" >> "$LOG"
    mark=$pass
    ((passed++))
  else
    echo "✗ $FINDING" >> "$LOG"
    mark=$fail
    failed=${failed:+$failed, }$label
  fi
  line "$mark"
}

# note <label> <claim> <test>...: like check, for a fact to read rather
# than a verdict: marked ○, never counted.
note() {
  label=$1
  claim=$2
  shift 2
  FINDING=""
  echo -e "\n$label: $claim" >> "$LOG"
  "$@" >> "$LOG" 2>&1
  echo "○ $FINDING" >> "$LOG"
  line ○
}

# line <mark>: the terminal's line for the current label and finding.
line() { printf '  %s %-9s  %s\n' "$1" "$label" "$FINDING"; }

# The mount table: every virtiofs mount, split by writability. Options come
# first so the path, last, keeps any spaces; list mode doesn't escape them.
rw_mounts=()
ro_mounts=()
while read opts target; do
  if [[ ,$opts, == *,ro,* ]]; then ro_mounts+=("$target"); else rw_mounts+=("$target"); fi
done <<< "$(findmnt -t virtiofs -ln -o OPTIONS,TARGET)"

# .git entries in writable mounts, pruning read-only mirror mounts.
git_scan() {
  prunes=()
  for m in "${ro_mounts[@]}"; do prunes+=(-path "$m" -prune -o); done
  (( ${#rw_mounts[@]} )) || return 0
  find "${rw_mounts[@]}" "${prunes[@]}" \( -name node_modules -o -name .venv \) -prune -o \
       -name .git "$@" -print
}

# --- Tests longer than one command -----------------------------------------

is_the_agent() {
  echo "built for: $LAB_AGENT"
  run id -un
  FINDING="runs as $OUT"
  [[ $OUT == "$LAB_AGENT" ]] || { FINDING+=", built for $LAB_AGENT"; return 1; }
}

public_egress() {
  run curl -sS --head --max-time 10 https://example.com || { FINDING=${OUT#curl: }; return 1; }
  read _ code _ <<< "$(head -1 <<< "$OUT" | tr -d '\r')"
  FINDING="HTTP $code from example.com"
  [[ $code == 200 ]]
}

public_dns() {
  run getent ahostsv4 example.com || { FINDING="example.com does not resolve"; return 1; }
  FINDING="example.com is ${OUT%% *}"
}

ipv6_off() {
  run cat /proc/sys/net/ipv6/conf/all/disable_ipv6 /proc/sys/net/ipv6/conf/default/disable_ipv6
  { read all; read default; } <<< "$OUT"
  FINDING="disable_ipv6: all $all, default $default"
  [[ $all == 1 && $default == 1 ]]
}

# The fence rejects, so the connect fails at once (curl exit 7). A timeout
# (28) or success (0) would mean the packet actually left.
private_unreachable() {
  refused=0
  left=0
  for addr in 10.0.0.1 172.16.0.1 192.168.0.1 169.254.169.254 100.64.0.1; do
    run curl -sS --max-time 5 "http://$addr/"
    if (( $? == 7 )); then ((refused++)); else ((left++)); fi
  done
  FINDING="$refused refused, $left left the guest"
  (( left == 0 ))
}

# Host content reaches the guest only through its mounts, so they show
# exactly what was handed in. Whether that matches intent is the host's call.
mounts_handed_in() {
  run findmnt -t virtiofs -ln -o OPTIONS,TARGET
  FINDING="${#rw_mounts[@]} read-write, ${#ro_mounts[@]} read-only"
}

ro_mounts_refuse_writes() {
  (( ${#ro_mounts[@]} )) || { FINDING="no read-only mounts"; return 1; }
  refused=0
  writable=0
  for m in "${ro_mounts[@]}"; do
    if run touch "$m/.lab-verify-$$"; then
      rm -f "$m/.lab-verify-$$"
      ((writable++))
    else
      ((refused++))
    fi
  done
  FINDING="$refused refused, $writable writable"
  (( writable == 0 ))
}

no_git_dirs() {
  run git_scan -type d -prune || { FINDING="scan failed"; return 1; }
  [[ -z $OUT ]] && { FINDING="none found"; return; }
  mapfile -t found <<< "$OUT"
  FINDING="${#found[@]} found"
  return 1
}

pointers_locked() {
  locked=0
  writable=0
  run git_scan -type f
  while read p; do
    [[ $p ]] || continue
    if run sh -c ': >> "$1"' sh "$p"; then ((writable++)); else ((locked++)); fi
  done <<< "$OUT"
  FINDING="$locked locked, $writable writable"
  (( writable == 0 ))
}

no_checks() {
  FINDING="no verify.bash"
  return 1
}

# --- The checks ------------------------------------------------------------

echo -e "Lab verify for $LAB_AGENT on $(hostname)\n"
echo Accounts
check agent "The shell runs as the agent this instance was built for." is_the_agent
check sudo "The agent cannot escalate." fails sudo -n true

echo -e "\nNetwork"
check egress "Public egress works." public_egress
check dns "Public names resolve." public_dns
check ipv6 "IPv6 is off." ipv6_off
check private "Private address space is unreachable." private_unreachable
check fence "The agent cannot use nft." fails nft list ruleset

echo -e "\nFilesystem"
note mounts "Host content reaches the guest only through these mounts." mounts_handed_in
check read-only "Every read-only mount refuses writes." ro_mounts_refuse_writes
check "git dirs" "No git metadata directory is reachable in any writable mount." no_git_dirs
check pointers "Every git pointer is locked." pointers_locked

for mixin in $LAB_MIXINS; do   # one mixin per word: split on purpose
  echo -e "\n${mixin^}"
  if [[ -r /lab/mixins/$mixin/verify.bash ]]; then
    . "/lab/mixins/$mixin/verify.bash"
  else
    check checks "Mixin $mixin brings its checks." no_checks
  fi
done

echo "────────────────────────────────────────────────────────────"
echo "$passed ok${failed:+, $((n - passed)) failed: $failed}. Evidence: ~/.lab/verify.log"
[[ -z $failed ]]
