#!/usr/bin/python3
"""Claude's mixed global file: recover selected user configuration.

Do not archive the whole file: it also holds account/machine/cache data. Keep
this supported preference list explicit; native user files live in state.tar.
MCP configuration is preserved as configured, including any embedded keys.
This filter excludes account fields; it does not make the snapshot secret-free.
"""
import json
from pathlib import Path
import sys

USER_KEYS = {
    "mcpServers", "projects", "theme", "preferredNotifChannel", "verbose",
    "autoCompactEnabled", "editorMode", "diffTool", "autoConnectIde",
    "showTurnDuration", "terminalProgressBarEnabled", "showSpinnerTree",
    "respectGitignore", "language", "outputStyle", "alwaysThinkingEnabled",
}
PROJECT_KEYS = {
    "allowedTools", "mcpContextUris", "mcpServers", "enabledMcpjsonServers",
    "disabledMcpjsonServers", "hasTrustDialogAccepted",
    "hasClaudeMdExternalIncludesApproved", "hasClaudeMdExternalIncludesWarningShown",
}


def read(path):
    try:
        data = json.loads(Path(path).read_text())
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected an object")
    if "projects" in data and (not isinstance(data["projects"], dict) or
                               any(not isinstance(value, dict) for value in data["projects"].values())):
        raise ValueError(f"{path}: invalid projects object")
    return data


def user_data(data):
    result = {key: value for key, value in data.items() if key in USER_KEYS}
    if "projects" in result:
        result["projects"] = {
            path: {key: value for key, value in project.items() if key in PROJECT_KEYS}
            for path, project in result["projects"].items()
        }
    return result


action, path = sys.argv[1:3]
try:
    data = read(path)
except (OSError, ValueError) as error:
    print(f"claude global configuration: {error}", file=sys.stderr)
    sys.exit(2 if action == "check" else 1)
if action == "check":
    sys.exit(0 if user_data(data) else 1)
elif action == "save":
    Path(sys.argv[3]).write_text(json.dumps(user_data(data), indent=2) + "\n")
elif action == "restore":
    snapshot = Path(sys.argv[3])
    if not snapshot.is_file():
        sys.exit("claude: missing global configuration snapshot; backup retained")
    saved = user_data(read(snapshot))
    # Preserve unrelated live keys (including a new login), and merge project
    # choices without replacing any already-present non-user metadata.
    projects = saved.pop("projects", {})
    data.update(saved)
    if projects:
        current = data.setdefault("projects", {})
        for project, choices in projects.items():
            current.setdefault(project, {}).update(choices)
    target = Path(path)
    temporary = target.with_name(target.name + ".lab-restore")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(target)
else:
    sys.exit(f"Unknown action: {action}")
