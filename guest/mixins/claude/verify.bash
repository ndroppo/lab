# Claude Code's checks. Sourced by verify.sh, using its check and run.

claude_installed() {
  run claude --version || { FINDING="not on the path"; return 1; }
  FINDING="$OUT, on the path"
}

claude_onboarded() {
  run python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(json.dumps(d.get("hasCompletedOnboarding")), d.get("lastOnboardingVersion", ""))' ~/.claude.json || { FINDING="~/.claude.json unreadable"; return 1; }
  read done version <<< "$OUT"
  FINDING="hasCompletedOnboarding = $done${version:+, version $version}"
  [[ $done == true && $version ]]
}

claude_transcripts() {
  run readlink -f ~/.claude/projects || { FINDING="projects path unreadable"; return 1; }
  [[ $OUT == /mnt/lab-state/claude/projects ]] || { FINDING="projects resolves to $OUT"; return 1; }
  run findmnt -T ~/.claude/projects -n -o FSTYPE,TARGET
  read fs target <<< "$OUT"
  [[ $fs == virtiofs && $target == /mnt/lab-state ]] || { FINDING="projects is not on the state mount"; return 1; }
  run python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("cleanupPeriodDays", 0))' ~/.claude/settings.json || { FINDING="settings unreadable"; return 1; }
  FINDING="projects on the state mount, retention $OUT days"
  [[ $OUT =~ ^[0-9]+$ ]] && (( OUT >= 36500 ))
}

check install "claude is on the agent's path and reports its version." claude_installed
check first-run "Claude Code's first-run onboarding is marked complete, so interactive claude doesn't stall on it." claude_onboarded
check transcripts "Claude's projects live on the state mount, with at least a century's retention." claude_transcripts
