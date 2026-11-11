#!/bin/bash
# Lab mixin: Claude Code. Runs as root on every boot, after base. Idempotent.

agent=$PARAM_LabAgentUser

# Set this up before Claude can write its first transcript. Everything on
# the state mount, including any planted symlink, is handled as the agent.
# ln refuses to replace a real projects directory: moving an old room's
# transcripts is a deliberate part of the user's cutover, not a boot action.
su - "$agent" <<'AGENT' || exit 1
umask 077
mkdir -p /mnt/lab-state/claude/projects "$HOME/.claude" || exit 1
ln -sfnT /mnt/lab-state/claude/projects "$HOME/.claude/projects" || exit 1
. /lab/mixins/claude/backup.bash
restore_on_boot || exit 1
python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}
before = json.dumps(settings, sort_keys=True)
# A century, rather than Claude's 30-day default. Keep a higher user value.
if settings.get("cleanupPeriodDays", 0) < 36500:
    settings["cleanupPeriodDays"] = 36500
# Lab is the sandbox, so Claude's permission prompts go, as Codex's sandbox
# does. Set every boot; a stricter session opts in with --permission-mode.
# The flag skips the one-time bypass warning a headless guest can't answer.
settings.setdefault("permissions", {})["defaultMode"] = "bypassPermissions"
settings["skipDangerousModePermissionPrompt"] = True
if json.dumps(settings, sort_keys=True) != before:
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
PY
AGENT

# Lab runs Anthropic's official installer, with the same trust as any Claude
# Code install. Claude Code updates itself, so skipping the install when
# it's already there does not let it go stale.
if [[ -z $(su - "$agent" -c 'command -v claude') ]]; then
  su - "$agent" -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi

version=$(su - "$agent" -c 'claude --version') || { echo "claude mixin: Claude Code did not install." >&2; exit 1; }
version=${version%% *}

# Without these flags, interactive claude stalls on first-run onboarding,
# which a headless guest can't complete. Restore or install supplies ~/.claude.json,
# the agent's, mode 600; rewriting it in place keeps both.
# Even this final merge runs as the agent: never follow a user-owned path
# with root's permissions, including a symlink recovered from user state.
printf -v version_arg '%q' "$version"
su - "$agent" -c "umask 077; python3 - \"\$HOME/.claude.json\" $version_arg" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
data = json.load(open(path))
data["hasCompletedOnboarding"] = True
data["lastOnboardingVersion"] = version
json.dump(data, open(path, "w"), indent=2)
PY
