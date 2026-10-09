#!/bin/bash
# Lab mixin: Claude Code. Runs as root on every boot, after base. Idempotent.

agent=$PARAM_LabAgentUser
home=$(getent passwd "$agent" | cut -d: -f6)

# Lab runs Anthropic's official installer, with the same trust as any Claude
# Code install. Claude Code updates itself, so skipping the install when
# it's already there does not let it go stale.
if [[ -z $(su - "$agent" -c 'command -v claude') ]]; then
  su - "$agent" -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi

version=$(su - "$agent" -c 'claude --version') || { echo "claude mixin: Claude Code did not install." >&2; exit 1; }
version=${version%% *}

# Without these flags, interactive claude stalls on first-run onboarding,
# which a headless guest can't complete. The installer creates ~/.claude.json,
# the agent's, mode 600; rewriting it in place keeps both.
python3 - "$home/.claude.json" "$version" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
data = json.load(open(path))
data["hasCompletedOnboarding"] = True
data["lastOnboardingVersion"] = version
json.dump(data, open(path, "w"), indent=2)
PY
