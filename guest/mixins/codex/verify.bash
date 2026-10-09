# Codex CLI's checks. Sourced by verify.sh, using its check and run.

# The mixin records the release it installed and a checksum for every file
# the bundle's bin/ held. Each must be unchanged, root-owned and executable,
# and codex, found on the agent's path, must report that release.
codex_installed() {
  record=/usr/local/share/lab/codex
  run cat "$record/version" || { FINDING="no install record"; return 1; }
  release=$OUT
  ok=0
  sums="checksums match"
  run sh -c 'cd /usr/local/bin && sha256sum -c "$1"' sh "$record/SHA256SUMS" || { sums="checksums differ"; ok=1; }
  binaries=0
  wrong=0
  while read _ name; do
    ((binaries++))
    run stat -c '%U %a' "/usr/local/bin/$name"
    [[ $OUT == "root 755" ]] || ((wrong++))
  done < "$record/SHA256SUMS"
  owned=root-owned
  (( wrong )) && { owned="$wrong not root 755"; ok=1; }
  FINDING="$release: $binaries binaries, $owned, $sums"
  run codex --version
  [[ ${OUT##* } == "$release" ]] || { FINDING+=", codex reports ${OUT##* }"; ok=1; }
  (( ok == 0 ))
}

codex_ripgrep() {
  run rg --version || { FINDING="not on the path"; return 1; }
  FINDING="${OUT%%$'\n'*}, on the path"
}

codex_config() {
  run python3 -c 'import json, sys, tomllib; c = tomllib.load(open(sys.argv[1], "rb")); print(json.dumps(c.get("sandbox_mode")), json.dumps(c.get("features", {}).get("daemon_auto_start")))' /etc/codex/config.toml || { FINDING="config unreadable"; return 1; }
  read sandbox daemon <<< "$OUT"
  FINDING="sandbox_mode = $sandbox, daemon_auto_start = $daemon"
  [[ $sandbox == '"danger-full-access"' && $daemon == false ]]
}

check install "Every binary from the Codex bundle is installed, root-owned, from one release." codex_installed
check ripgrep "ripgrep, which Codex searches with, is on the agent's path." codex_ripgrep
check config "Codex's system config turns off its own sandbox and its background daemon." codex_config
