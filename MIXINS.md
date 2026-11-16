# Writing mixins

A mixin adds a tool or service inside a Lab room. It lives in `guest/mixins/<name>/` in your Lab installation and is selected when creating or rebuilding a room. The [README](README.md) covers using Lab; this guide covers adding a capability.

## Add a tool

For a tool-only mixin named `tree`, create `guest/mixins/tree/` with these two files. `provision.bash` runs as root on every boot, after base provisioning, so setup must be safe to repeat:

```bash
#!/bin/bash
# provision.bash
apt-get -q install -y tree
```

`verify.bash` is sourced by `verify.sh` as the agent. Define a test and register it with `check`:

```bash
# verify.bash
tree_installed() {
  run tree --version || { FINDING="tree is unavailable"; return 1; }
  FINDING=${OUT%%$'\n'*}
}
check tree "tree is installed." tree_installed
```

`check` takes a label, a claim and a test command. The test returns success or failure and sets `FINDING` to what it observed. `run` records a command's output and exit status in the verification log and supplies its output as `OUT`. A mixin without `verify.bash` fails room verification.

## Try it

From your Mac, exit any running room and create a test room. Here `mixin-test` is an example name; select the `tree` mixin when asked:

```sh
lab create --instance mixin-test
lab --instance mixin-test verify.sh
lab --instance mixin-test tree .
```

After changing provisioning, use `lab --instance mixin-test rebuild` before rerunning the checks. No change to the launcher is needed to add the mixin: it discovers directories containing `provision.bash`. Names must start with a letter or digit and contain only letters, digits, `_`, `.` or `-`.

## Execution and edits

Selected mixin directories are mounted read-only at `/lab/mixins/<name>`; unselected ones are not mounted or provisioned. Common tools are also read-only at `/lab/bin`, on the agent's `PATH`. Your installer can put commands in `/usr/local/bin` or another guest PATH directory, not in the mounted directories. No mixin script runs on the host.

Provisioning receives the agent account as `PARAM_LabAgentUser`. Run operations on agent-owned files as that agent, not as root through writable paths. Runtime scripts can source `/etc/lab.env` for `LAB_AGENT` and `LAB_MIXINS`. Keep guest-local user state in the agent's home, or use a mixin-specific directory under `/mnt/lab-state/` for state that should survive rebuilds.

Provisioning scripts are embedded when a room is created. Changes to `provision.bash`, mount declarations or default-harness selection need a create/rebuild to take effect. Runtime helpers such as `verify.bash` and `backup.bash` are read directly from the mounted directory, so edits to those apply without rebuilding.

## Offer a default harness

Add an empty `harness` file if the mixin installs a command with the same name that should be offered as the default at setup. Without this marker, the installed commands remain usable, but the mixin is not offered as a default harness.

## Mount extra host data

An optional `mounts` file declares read-only host data. Each row contains a parameter name, a source and a guest destination, separated by literal tabs. The Git mixin uses:

```text
LabGitOrigin	@LabGitStore	/mnt/lab-git
```

This supplies the resolved host path as `PARAM_LabGitOrigin` during provisioning and mounts it read-only at `/mnt/lab-git`. Currently `@LabGitStore` is the only allowed source; arbitrary host paths and shell expressions are not accepted. A path parameter alone does not mount anything.

Parameter names must be unique, and destinations must be absolute and not overlap other mounts. Lab checks declarations against its path guards and includes them in the confirmation summary. Exact validation rules are in `mixin_resources` and `resource_walls` in [the launcher](bin/lab).

## Back up user state

An optional `backup.bash` defines `backup` and `restore` functions. The `backup.sh` coordinator sources it in a separate subshell as the agent, supplies `BACKUP=/mnt/lab-state/backup`, and serializes its own invocations. Keep your archives under `$BACKUP/<name>/`, refuse active writers when necessary, and retain the last successful snapshot if a new one fails. Restore must not overwrite unrelated existing user state. The [common archive helpers](guest/bin/backup.bash) and [Claude's backup hook](guest/mixins/claude/backup.bash) show how existing mixins handle this.

Automatic boot recovery needs a separate, explicit call from provisioning, as the agent, before installation or launch writes user state. Follow Claude's `restore_on_boot` pattern: set `BACKUP` yourself because the coordinator is not running, skip established user state on ordinary boots, and restore only a fresh setup or an interrupted recovery. Do not call `restore` unconditionally on every boot. See [Claude's provisioning](guest/mixins/claude/provision.bash) for the call site. The Git mixin instead restores branches only on an explicit `backup.sh --restore`.

The archive helpers preserve symlinks without following their targets, so external targets need their own persistence. The common tools already back up and restore `~/.agents/skills`; they do not create links from harness skill directories to it.
