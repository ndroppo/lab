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

check install "claude is on the agent's path and reports its version." claude_installed
check first-run "Claude Code's first-run onboarding is marked complete, so interactive claude doesn't stall on it." claude_onboarded
