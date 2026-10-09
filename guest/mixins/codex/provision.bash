#!/bin/bash
# Lab mixin: Codex CLI. Runs as root on every boot, after base. Idempotent.
#
# Lab is the sandbox. Codex ships its own (bubblewrap and user namespaces,
# on Linux); Lab installs none of it and turns it off in Codex's own config,
# so Codex runs directly in the room the walls already enclose.
#
# Installed from upstream's bundle, one download per release: every file in
# its bin/ goes side by side into /usr/local/bin (Codex finds
# codex-code-mode-host as a sibling, and runs tool calls only through it);
# its resources (bwrap, zsh, voice) and its bundled ripgrep are left behind.
# Codex doesn't update itself unasked, so every boot checks the latest
# release and reinstalls when it differs: packages go stale.

bindir=/usr/local/bin
record=/usr/local/share/lab/codex   # the installed release: version, SHA256SUMS
asset=codex-package-$(uname -m)-unknown-linux-musl.tar.gz
installed=""
[[ -f $record/version ]] && installed=$(cat "$record/version")

release=$(curl -fsSL https://api.github.com/repos/openai/codex/releases/latest)
if [[ -z $release ]]; then
  [[ $installed ]] || { echo "codex: GitHub unreachable and codex is not installed." >&2; exit 1; }
  echo "codex: GitHub unreachable; keeping installed codex $installed." >&2
else
  read latest url digest <<< "$(python3 -c '
import json, sys
release = json.load(sys.stdin)
asset = next(a for a in release["assets"] if a["name"] == sys.argv[1])
version = release["tag_name"].rsplit("v", 1)[-1]
print(version, asset["browser_download_url"], asset["digest"].removeprefix("sha256:"))
' "$asset" <<< "$release")"

  if [[ $latest == "$installed" ]]; then
    echo "codex: $installed is current."
  else
    echo "codex: installing $latest (installed: ${installed:-none})."
    work=$(mktemp -d)
    curl -fsSL "$url" -o "$work/codex.tar.gz"
    actual=$(sha256sum "$work/codex.tar.gz" | cut -d' ' -f1)
    if [[ $actual != "$digest" ]]; then
      echo "codex: checksum mismatch (expected $digest, got $actual); not installing." >&2
      exit 1
    fi
    tar -xzf "$work/codex.tar.gz" -C "$work" bin
    # The previous release's binaries go first, so none outlives its release.
    [[ -f $record/SHA256SUMS ]] && while read _ name; do rm -f "$bindir/$name"; done < "$record/SHA256SUMS"
    install -o root -g root -m 755 "$work"/bin/* "$bindir/"
    mkdir -p "$record"
    (cd "$work/bin" && sha256sum -- *) > "$record/SHA256SUMS"
    echo "$latest" > "$record/version"   # last, so an interrupted install retries
    rm -rf "$work"
  fi
fi

# Codex searches with ripgrep; the distribution's, current every boot like
# base's packages, rather than the bundle's copy.
apt-get -q install -y ripgrep

# Codex's system config, two keys, each a default the user layer can
# override rather than an enforced requirement. Merge, never overwrite: Lab
# owns these and leaves every other line alone.
#   sandbox_mode = "danger-full-access": Lab is the sandbox; opting back in
#     only makes Codex stricter.
#   [features] daemon_auto_start = false: interactive codex otherwise tries
#     to start a long-running background daemon, which fails here; the room
#     stops on exit, so a daemon would have nothing to outlive anyway.
install -d -m 755 /etc/codex
python3 - /etc/codex/config.toml <<'PY'
import re, sys, tomllib
path = sys.argv[1]
try:
    text = open(path).read()
except FileNotFoundError:
    text = ""
config = tomllib.loads(text)
lines = text.splitlines(keepends=True)
if lines and not lines[-1].endswith("\n"):
    lines[-1] += "\n"

def header(line):
    m = re.match(r"\s*\[+([^\]]+)\]", line)
    return m and m.group(1).strip()

# sandbox_mode, top level: any existing line there goes, then it leads the file.
if config.get("sandbox_mode") != "danger-full-access":
    kept, top = [], True
    for line in lines:
        top = top and not header(line)
        if not (top and re.match(r"\s*sandbox_mode\s*=", line)):
            kept.append(line)
    lines = ['sandbox_mode = "danger-full-access"\n'] + kept

# daemon_auto_start, in [features]: replaced there, or the table added.
if config.get("features", {}).get("daemon_auto_start") is not False:
    kept, section = [], None
    for line in lines:
        section = header(line) or section
        if section == "features" and re.match(r"\s*daemon_auto_start\s*=", line):
            continue
        kept.append(line)
        if header(line) == "features":
            kept.append("daemon_auto_start = false\n")
    if "features" not in config:
        kept += ["\n[features]\n", "daemon_auto_start = false\n"]
    lines = kept

new = "".join(lines)
tomllib.loads(new)   # never write a file Codex couldn't read
if new != text:
    open(path, "w").write(new)
PY
