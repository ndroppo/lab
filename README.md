# lab

A walled room for AI agents.

Coding agents like Claude Code and Codex work best when they can run commands freely. Lab gives them a place to do that: a Linux virtual machine on your Mac where the agent can see only the folders you choose, can reach the public internet but not your local or private networks, and has no admin rights. You type `lab`, your agent starts inside the room. When the last session leaves, the room shuts down.

## Requirements

- A Mac with Apple Silicon.
- [Lima](https://lima-vm.io) 2.2.0 or later, which runs the virtual machine.
- `git`.
- macOS's `/usr/bin/perl`, used only for kernel file locking; no additional Perl packages.

## Install

Clone this repo into `~/.lab`, and add `~/.lab/bin` to your `PATH` in your shell profile:

```
git clone https://github.com/ndroppo/lab.git ~/.lab
echo 'export PATH="$HOME/.lab/bin:$PATH"' >> ~/.zshrc
```

Then open a new terminal. `~/.lab` is also where Lab keeps your keys, your repos' protected git data, and each room's persistent state.

Never share `~/.lab`, a folder inside it, or a folder containing it, such as your home folder. Lab refuses those user mounts: an agent that could edit Lab could change what Lab runs on your Mac, and keys and state belong to their own rooms. Lab supplies its own narrowly scoped mounts instead.

## First run

`cd` to the folder you want to work in and run `lab`. It asks:

1. **Folders the agent may change.** Your project folders, typically. Each appears inside the room at the same path it has on your Mac.
2. **Folders the agent may only read.** Reference material, say. One can sit inside a writable folder to protect part of it.
3. **Which capabilities to install.** Mixins add tools and services. Claude Code and Codex provide agent harnesses; `git` adds optional Git integration for shared projects. Say yes to the ones you want.
4. **Which harness to start by default.** Choose from the harnesses you selected, not every mixin. With one harness, Lab chooses it without asking; with none, it opens a shell, even if other capabilities such as `git` are installed.

Lab shows what it will build and asks you to confirm. The first build downloads an Ubuntu image and installs everything, so it takes a while. Your chosen harness then starts as the agent user, in the folder you started from if you shared it, or in the agent's home folder if you didn't.

Exit the harness to leave. The last session out shuts the room down, and the next `lab` starts it again, in about 15 seconds. `lab bash` opens the agent's shell instead; type `exit` to leave that.

## Signing in

**Claude Code:** on your Mac, run `claude setup-token`, then save the token it prints as a file named `CLAUDE_CODE_OAUTH_TOKEN` in `~/.lab/secrets/lab/`. The token lasts about a year.

**Codex:** run `lab codex login` and finish in your Mac's browser. The sign-in stays inside the room; rebuilding the room means signing in again.

Each file in `~/.lab/secrets/lab/` becomes an environment variable of the same name inside the room, so any tool that reads its key from the environment can get it the same way. Lab copies them in each time the room starts, so a changed key takes effect at the next `lab`.

One caution for Codex: if it finds an `OPENAI_API_KEY` and you haven't signed in, it uses the key and bills your API account. Leave that key out of a room you use with a ChatGPT plan.

## Day to day

```
lab                 start the default harness, creating the room if needed
lab codex           run codex in the room
lab bash            open the agent's shell instead
lab git status      run a command with its arguments
lab create          create a room without starting it
lab rebuild         rebuild a room, offering its current answers as defaults
lab harden          protect the git repos in your shared folders (see below)
lab unharden <repo>  move one repo's protected metadata home; --all for all
lab uninstall       restore repos, delete Lab's rooms, then remove ~/.lab
```

The launch grammar is `lab [lab options] <command> [args...]`. Lab options and their values come first. The first positional argument names the guest command; everything after it belongs to that command, unchanged, even if it looks like a Lab option or verb. No separator is required:

```
lab --instance research claude --agent researcher
lab -- --version
```

Bare `lab` starts the configured default, or Bash if there is none. `lab -- [args...]` passes arguments to that same default. Named commands need only be executable on the agent's `PATH`; they are not checked against mixins. Every command receives the login environment and keys, starts in the same landing directory, and uses the same session lifecycle and Git exit check. A missing command is reported clearly and returns 127.

`create`, `rebuild`, `harden`, `unharden`, and `uninstall` are Lab's administrative verbs. A first positional argument matching one selects that verb, not a guest command. Use `lab bash` to run a guest command with a colliding name. Mixin names themselves are unrestricted by Lab's verbs.

- **To change the folders or agents,** run `lab rebuild`. It erases the guest's disk and builds it fresh. Shared folders and transcripts on the state mount are untouched. Guest-only files, settings, sign-ins and Codex's resume index are lost.
- **Older instances** that mount the whole `guest/` tree need rebuilding before this launcher can start them. Save guest-only work and transcripts first. Rebuild offers the current mounts, mixins and default harness back as defaults.
- **More than one room:** add `--instance <name>` when starting, creating, rebuilding or hardening, for example a separate room for a separate project. Each room has its own folders, agents, and keys, in `~/.lab/secrets/<name>/`. Only one runs at a time. `unharden` is repo/store-wide and `uninstall` removes all Lab-built rooms; neither accepts `--instance`.
- **More than one session:** run `lab` again in another terminal to join the same room, without rebooting it. Each entry runs the host checks and refreshes keys. Leaving one session does not interrupt the others; only the last departure stops the VM. Every departure still runs the Git metadata check, even while other sessions remain. Tracking covers sessions opened with `lab`; direct `limactl` or SSH administration bypasses its lifecycle coordination.
- **To preview without changing anything,** add `-n`.
- **Other options:** `--yes` accepts every default without asking, except uninstall's confirmation; `--cpus`, `--memory`, and `--disk` size the virtual machine; `--show` prints the Lima configuration Lab generates. `lab --help` lists them all.

Lab leaves other Lima virtual machines alone. It won't start, rebuild, or delete one it didn't create.

## Mixins

Lab discovers capabilities from the directories actually present under `~/.lab/guest/mixins/`; it has no built-in list of mixin names. They still ship in this repo, but each directory is intended to be independently distributable. A room receives only the common `guest/bin/` tools and its selected mixin directories, all read-only. Unselected mixins' code is not mounted or provisioned.

Each mixin supplies `provision.bash` (root provisioning inside the guest) and `verify.bash` (checks sourced by `verify.sh`). An optional empty `harness` file offers the mixin's command as a default candidate at create; it does not restrict named commands. No mixin script runs on the host.

A mixin needing extra host data can supply a `mounts` file. Each tab-separated row declares a parameter name, a host source and a guest destination. Sources must reference core path facts such as `@LabGitStore`; declarations cannot name arbitrary host paths or expand environment variables. Lab resolves the source, passes it as `PARAM_<name>` to provisioning, and mounts it read-only. References are data, not shell expressions. All declarations pass the same host guards and appear in the confirmation summary; they cannot expose secrets, Lab's code or another room's state. Writable persistence uses the room's existing state mount.

The Git mixin declares its origin this way. The protected host store's location is a core fact needed by `harden`, even without that mixin; knowing its path does not mount it or initialize guest Git metadata.

## What survives a rebuild

Every room has a private directory on your Mac, `~/.lab/state/<instance>`, mounted read-write at `/mnt/lab-state` in that room alone. Lab creates it with mode 700; don't commit its contents, which can contain everything a session printed.

The Claude Code mixin links `~/.claude/projects` to `claude/projects` on that mount and raises transcript retention to at least 100 years. The Codex mixin links `~/.codex/sessions` to `codex/sessions` there. Transcripts are written directly to your Mac, with no copy-on-exit step. Claude Code can resume them after a rebuild. Codex's rollouts survive directly; its resume index stays on the guest's disk and is saved by `backup.sh`.

Run `lab backup.sh` before rebuilding. It saves the selected mixins' recoverable state to `backup/` on the mount: Codex's index and SQLite files (including journals), and a complete Git bundle of every local branch in each initialized shared-project copy. Stop Codex first; the script refuses while it or its helpers are running. Each successful snapshot replaces that mixin's previous generation; a failed snapshot leaves its previous backup intact. Working files already live in your shared folders; uncommitted/staged Git index state, tags, credentials and harness configuration are not part of this backup.

On the first boot after rebuild, the Codex mixin restores its saved index before any harness launches, as the agent, and consumes that backup only after a successful restore. It never overwrites an existing index. Run `lab backup.sh --restore` before resuming work to restore Git branches; this keeps the bundles and never checks out or writes shared working files. Already-restored histories are left alone; different later history or staged work is refused rather than overwritten. A fresh metadata copy initialized by `git status` is also safe to restore.

Credentials and harness configuration stay off the state mount. Sign in to Codex again after rebuilding. The mount is not a backup against deletion: the agent can change or delete its contents, just like any other writable shared folder.

To keep a room's state elsewhere, create its directory there and symlink `~/.lab/state/<instance>` to it before creating the room. Lab resolves that path at create and every start, and refuses one pointing into its code, secrets, git store, Lima's state or another room's state. It also refuses user mounts exposing state, including relocated directories. If the directory has gone, Lab recreates it empty at start; a dangling symlink must be repaired first.

An older instance needs `lab rebuild` to gain the state mount and transcript links. Save its existing transcripts first; Lab does not migrate guest-only files for you.

## Git

Git protection is part of every room. Git integration inside shared projects is optional.

A repo's `.git` folder can hold hooks and settings that git runs automatically, so an agent able to write there could plant something that runs on your Mac, as you, the next time you use git. The first time you start a room with repos in its writable folders, Lab stops and tells you to run `lab harden`. That moves each repo's `.git` folder to `~/.lab/git` and leaves a small locked file pointing there.

Without the `git` mixin, that pointer leads nowhere inside the room. The files are still shared and editable; native Git is available for guest-local repos and clones, but it cannot see your hardened host metadata. Tools requiring a Git repo may need their usual non-repo override.

Run `lab harden` again whenever you clone a new repo into a shared folder. Lab won't start until you do. When you leave the room, Lab checks again and warns you if a `.git` directory or unprotected pointer appeared during the session. Look before you run git there.

The scan includes dependency directories such as `node_modules` and `.venv`; neither is exempt from the git wall. An unlocked `.git` file can point at metadata under any name, and a `.git` symlink is not a protected pointer. Both are flagged. `harden` reports such pointers for inspection instead of automatically trusting them. A failed scan also stops launch rather than reporting a clean room. These checks protect hardened host metadata; they do not certify arbitrary agent-created directories or bare repositories as safe inputs to host Git.

### Optional Git integration

Select the `git` mixin at create or rebuild to get independent, agent-owned Git metadata against the same shared files. Only then does Lab mount the host store read-only at `/mnt/lab-git`, prepare the guest's metadata root and install its wrapper. Enabling or disabling the mixin takes a rebuild.

The wrapper creates a repo's private metadata copy on its first use, at the path named by the locked pointer. Later boots fetch into that copy on its first use; repos you don't use are left alone. The copy has its own index, objects and configuration, not the host's hooks or remotes. Calling `/usr/bin/git` directly bypasses this convenience sync, not a security wall.

Host branches appear as `origin/main`, `origin/feature`, and so on. The first local branch is `agent`, starting at the host's current HEAD, or unborn if the host repo has no commits. Every local branch is the agent's; `git switch main` does not silently make one from `origin/main`. Ordinary commits, branching and switching work. Fetching changes only remote-tracking refs, never the checked-out branch, its index or the shared files. Host edits therefore appear as unstaged changes against the agent's branch. To restore the host version of a file, use `git restore --source=origin/main -- <file>`.

**The files are shared, not separate checkouts.** Switching a guest branch changes the files on your Mac too. Guest commits and branches stay on the guest's disk; preserve them with `lab backup.sh` before a rebuild and `lab backup.sh --restore` afterward. Publishing still means reviewing and committing the shared files on your Mac. Delivery of guest commits is not built yet. Guest commits use the agent's name and `<agent>@localhost` email.

The host store is readable in the room, so do not embed credentials in repo configuration or hooks. Lab does not import your host's credential manager.

For an older instance, rebuild and select `git` to use the integration. In a new room, run `git status` once in a repo if a harness examines it before making any git call: that creates its metadata copy. Harness-specific directory-trust decisions are still yours.

### Undo hardening

Exit every Lab room first. On your Mac:

```
lab unharden <repo>
lab unharden --all
```

This unlocks and removes each protected pointer, then moves its metadata home. It refuses while a Lab instance is running. `-n` previews the moves. It does not treat a linked Git worktree's pointer as a hardened repo. If Git cannot open a repo after its move, Lab rolls it back. Guest metadata copies are left alone until rebuild.

`--all` matches store entries back to their repo pointers, not just their path names. Histories whose repos have moved or disappeared are reported as orphans and left untouched. The default store is `~/.lab/git`; `LAB_GIT_STORE` selects another.

## Uninstall

Run `lab uninstall -n` to see the plan, then `lab uninstall`. It always asks for confirmation, even with `--yes`. It stops Lab's running rooms, moves live repos' protected metadata home, deletes Lab-built instances, and removes the `~/.lab` entry. A failed metadata move stops deletion so you can fix it and rerun. Lima and instances Lab did not build are left alone.

The plan names what will be deleted or kept: rooms, repo histories, credentials, and each room's persistent state, which may include transcripts, backups and delivery bundles you have not fetched. Orphaned histories inside the removed tree go with it. Save anything you need first.

**Relocation links preserve external targets.** Uninstall removes symlinks rather than deleting their targets, including linked state, secrets, the Git store, or `~/.lab` itself. External Git stores are retained after live histories move home; their orphan histories remain too. Dangling data links do not prevent uninstall. A target inside the deleted tree still goes with that tree, regardless of links pointing to it. There is no option to delete relocated contents automatically.

Remove the `~/.lab/bin` PATH line you added to your shell profile afterward; Lab never edits your profile.

## What Lab protects, and what it doesn't

Inside the room, the agent:

- sees only the folders you shared, plus Lab's guest files read-only and its own state read-write; the optional Git mixin also exposes the protected git store read-only;
- can reach the public internet, but not private addresses: your home or office network, cloud metadata services, and the like;
- runs as its own ordinary user, with no admin rights;
- can't change the network rules, reach your keys folder or Lima's own files, or write your Mac's protected git metadata.

What it can still do:

- **Change or delete anything in a folder you shared as writable.** That's the point of sharing it. Use version control, and share read-only what the agent only needs to read.
- **Send what it can read to the internet.** It has the public internet, so don't share what shouldn't leave your Mac.
- **Read its own keys.** The agent's tools use those keys, so it can see them, just as in any other sandbox.

Codex has its own sandbox, which Lab turns off: the room is already the sandbox. A startup warning that `bwrap` is missing is expected.

## Checking the room

Run `lab verify.sh`. It tests each of the protections above from inside the room and prints one line per test:

```
Network
  ✓ egress     HTTP 200 from example.com
  ✓ private    5 refused, 0 left the guest
  ✓ fence      refused: Operation not permitted (you must be root)
```

✓ passed, ✗ failed. A tally at the end names any failures. Everything each test ran, with its full output, is saved inside the room, in `~/.lab/verify.log`.
