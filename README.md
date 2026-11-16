# lab

A walled room for AI agents. Lab runs Claude Code, Codex and other commands in a Linux VM on your Mac. You choose which folders it can read or change. The agent can reach the public internet, but not your local or private networks, and has no admin rights.

## Install

You need an Apple Silicon Mac, [Lima](https://lima-vm.io) 2.2.0 or later, and `git`. Clone Lab and add it to your shell's `PATH`:

```sh
git clone https://github.com/ndroppo/lab.git ~/.lab
echo 'export PATH="$HOME/.lab/bin:$PATH"' >> ~/.zshrc
```

For Bash, use `~/.bash_profile` instead of `~/.zshrc`. Open a new terminal afterward.

## First run

```sh
cd ~/your-project
lab
```

Lab asks which folders to share read-write or read-only, which optional tools ([mixins](MIXINS.md)) to install, and which agent harness to start. After you confirm the choices, Lab builds the room and installs your chosen harness there; no Mac-side harness installation is needed. With no harness selected, Lab opens a shell. The first build takes a while, but later runs reuse the room. If the harness asks for sign-in, exit it and follow the steps below.

Shared folders appear at the same paths as on your Mac. Lab refuses to share `~/.lab`, anything inside it, or a parent such as your home folder. If it finds unprotected Git repos in your writable folders, it asks you to run `lab harden`, then `lab` again. This protects their Git metadata without moving your working files.

## Signing in

**Claude Code:** run its token setup inside the room:

```sh
lab claude setup-token
```

Open the displayed URL in your Mac's browser and sign in with your Claude subscription. Paste any authorization code back into the waiting terminal. Copy the resulting token, then save it on your Mac:

```sh
mkdir -p ~/.lab/secrets/lab
(umask 077; cat > ~/.lab/secrets/lab/CLAUDE_CODE_OAUTH_TOKEN)
```

Paste the token, press Return, then Ctrl-D. The next `lab` uses it; the token lasts about a year and survives rebuilds. The same directory supplies other environment variables: each file's name becomes the variable name and its contents become the value, refreshed on every entry.

**Codex:** run `lab codex login` and sign in to your ChatGPT account using your Mac's browser. This login is stored inside the VM, so repeat it after a rebuild. For separately billed OpenAI API access instead of a ChatGPT subscription, use `OPENAI_API_KEY`; otherwise, leave it unset.

## Use

```text
lab                 start the default harness
lab claude          run Claude Code
lab codex           run Codex
lab bash            open the agent's shell
lab git status      run a command in the room
lab verify.sh       check protections and installed tools
lab create          configure a room without starting it
lab --help          list options
```

Exit the harness or shell to leave. Running `lab` in another terminal joins the same room; the last session out stops it.

To keep different setups, use `lab --instance <name>` to create or enter a named room. Choose the name yourself: `lab --instance research codex`, for example, runs Codex in a room named `research`. Each room keeps its own folders, tools, state and keys, so you can switch setups without rebuilding. Exit all sessions in one room before starting another, and put its keys in `~/.lab/secrets/<name>/`. Lab options go before the guest command; arguments after the command go to it unchanged.

## Git

Git metadata can contain hooks and settings that execute on your Mac. `lab harden` moves it into protected storage and leaves a locked pointer in each repo. Run it again after cloning a new repo into a writable shared folder. Lab refuses to start with exposed metadata and warns if any appears during a session; inspect it before using Git on your Mac.

The optional `git` mixin gives the agent its own branches and history against your shared working files. Host branches appear as `origin/main`, `origin/feature`, and so on, and host metadata is readable but not writable from the room; credentials embedded there are readable too. **The working files are still shared:** switching a guest branch changes the files on your Mac. To publish work, review and commit those files on your Mac. Without the mixin, the shared files remain editable but their protected Git metadata is unavailable inside the room.

## Rebuilding

Rebuild to change shared folders or mixins, or apply updated guest setup. **The guest disk is erased; shared folders and persistent state on your Mac are kept.** Run these steps from your Mac, stopping if any step fails. For a named room, include `--instance <name>` in every command:

1. Exit all harnesses and guest shells. Save any guest-only files not covered below.
2. Run `lab backup.sh` and wait for `Backup complete`.
3. Run `lab rebuild`. Your current choices are offered as defaults; keep the mixins whose state you want restored.
4. Run `lab backup.sh --restore` before resuming work. Harness state restores automatically at boot; this command also restores Git branches without changing shared working files.
5. Renew Codex and other guest-only sign-ins, including MCP sign-ins. Claude's host-side token remains available.

Transcripts are saved continuously to `~/.lab/state/<instance>` on your Mac. `backup.sh` saves harness settings, profiles, instructions, skills and history, `~/.agents/skills`, and local Git branches. If you include sensitive information in conversations or saved settings, it can also appear in transcripts or backups.

Known sign-in files, Git staging and tags, and unrelated guest-only files are excluded from backups. Symlinks are saved, not their external targets. State survives rebuilds but remains writable by the agent; to recover from changes or deletion, keep an independent backup outside the room's writable folders.

## Safety and checks

The agent can **change or delete writable shared files, send anything it can read to the internet, and read the credentials supplied to its tools**. Lab turns off Claude's permission checks and Codex's own sandbox; the VM is the sandbox. For a stricter Claude session, use `lab claude --permission-mode auto`.

`lab verify.sh` checks protections observable inside the room and prints pass/fail results, with full evidence in the guest's `~/.lab/verify.log`. Host mount and Git checks run before each entry.

## Removal

To undo Git hardening without removing Lab, exit all rooms and run `lab unharden <repo-path>`, or `lab unharden --all`. This operates on host repos, not rooms; `--instance` does not apply.

To remove Lab, preview with `lab uninstall -n`, then run `lab uninstall`. It asks for confirmation, restores live repos' Git metadata, and removes Lab's rooms and `~/.lab`, including credentials, transcripts and backups stored there. Save anything you need first. Relocated data outside that tree is retained; Lima and other VMs are left alone. Remove Lab's `PATH` line from your shell profile afterward.
