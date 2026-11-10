# lab

A walled room for AI agents.

Coding agents like Claude Code and Codex do their best work when they can run commands freely. Lab gives them a Linux virtual machine on your Mac to do that in. Inside it, the agent sees only the folders you share, has no admin rights, and can reach the public internet but not your local or private networks. Type `lab` and your agent starts inside the room. The room shuts down when the last session leaves.

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

Every launch follows `lab [lab options] <command> [args...]`. Lab options and their values come first. The first positional argument names the command to run in the guest, and everything after it goes to that command unchanged, even when it looks like a Lab option or verb. You don't need a separator:

```
lab --instance research claude --agent researcher
lab -- --version
```

Bare `lab` starts the configured default, or Bash if no default is set. `lab -- [args...]` passes arguments to that same default. A named command only has to be executable on the agent's `PATH`, and Lab does not check it against mixins. Every command gets the login environment and keys, starts in the same landing directory, and goes through the same session lifecycle and Git exit check. If the command is missing, Lab says so clearly and returns 127.

`create`, `rebuild`, `harden`, `unharden`, and `uninstall` are Lab's administrative verbs. When the first positional argument matches one of them, Lab runs that verb instead of a guest command. To run a guest command whose name collides with a verb, use `lab bash`. Lab's verbs put no restriction on mixin names.

- **To change the folders or agents,** run `lab rebuild`. It erases the guest's disk and builds a fresh one. Shared folders and transcripts on the state mount stay as they are. Guest-only files, settings, sign-ins, and Codex's resume index are lost.
- **Older instances** that mount the whole `guest/` tree must be rebuilt before this launcher can start them. Save guest-only work and transcripts first. Rebuild offers the current mounts, mixins, and default harness back to you as defaults.
- **More than one room:** add `--instance <name>` when starting, creating, rebuilding, or hardening, for example to give a separate project its own room. Each room has its own folders, agents, and keys, with the keys kept in `~/.lab/secrets/<name>/`. Only one room runs at a time. `unharden` applies to the whole repo and store, and `uninstall` removes every room Lab built. Neither one accepts `--instance`.
- **More than one session:** run `lab` again in another terminal to join the same room without rebooting it. Each new entry runs the host checks and refreshes keys. Leaving one session doesn't interrupt the others, and the VM stops only when the last session leaves. Every departure still runs the Git metadata check, even while other sessions remain open. Lab tracks only sessions opened with `lab`. If you administer the VM directly with `limactl` or SSH, you bypass Lab's lifecycle coordination.
- **To preview without changing anything,** add `-n`.
- **Other options:** `--yes` accepts every default without asking, except the uninstall confirmation. `--cpus`, `--memory`, and `--disk` set the virtual machine's size. `--show` prints the Lima configuration Lab generates. `lab --help` lists them all.

Lab leaves other Lima virtual machines alone. It won't start, rebuild, or delete a VM it didn't create.

## Mixins

Lab finds mixins by reading the directories present under `~/.lab/guest/mixins/`. It has no built-in list of mixin names. The mixins ship in this repo, but each directory is meant to be distributable on its own. A room gets only the common `guest/bin/` tools and the mixin directories selected for it, all mounted read-only. Code from unselected mixins is neither mounted nor provisioned.

Each mixin supplies `provision.bash`, which provisions the guest as root, and `verify.bash`, which holds checks that `verify.sh` sources. An optional empty `harness` file offers the mixin's command as a default candidate at create time. It places no limit on which commands you can name. No mixin script runs on the host.

A mixin that needs extra data from the host can supply a `mounts` file. Each tab-separated row declares a parameter name, a host source, and a guest destination. Sources must reference core path facts such as `@LabGitStore`. A declaration cannot name an arbitrary host path or expand environment variables. Lab resolves the source, passes it to provisioning as `PARAM_<name>`, and mounts it read-only. Lab treats each reference as data and never evaluates it as a shell expression. Every declaration goes through the same host guards and appears in the confirmation summary, and none can expose secrets, Lab's code, or another room's state. For writable persistence, a mixin uses the room's existing state mount.

The Git mixin declares its origin this way. `harden` needs the location of the protected host store even when that mixin isn't selected, so the location is a core fact. Knowing the path does not mount the store or initialize Git metadata in the guest.

## What survives a rebuild

Each room has a private directory on your Mac, `~/.lab/state/<instance>`, mounted read-write at `/mnt/lab-state` in that room and no other. Lab creates it with mode 700. Don't commit what's in it, because it can hold everything a session printed.

The Claude Code mixin links `~/.claude/projects` to `claude/projects` on that mount and raises transcript retention to at least 100 years. The Codex mixin links `~/.codex/sessions` to `codex/sessions` on the same mount. Transcripts go straight to your Mac, so nothing has to be copied out on exit. Claude Code can resume them after a rebuild. Codex's rollouts survive the same way, but its resume index lives on the guest's disk, and `backup.sh` saves it.

Run `lab backup.sh` before rebuilding. It saves the recoverable state of the selected mixins to `backup/` on the mount: Codex's index and SQLite files, journals included, and a complete Git bundle of every local branch in each initialized shared-project copy. Stop Codex first, because the script won't run while Codex or its helpers are running. A successful snapshot replaces that mixin's previous generation, and a failed one leaves the previous backup intact. Your working files already live in your shared folders. The backup does not include uncommitted or staged Git index state, tags, credentials, or harness configuration.

On the first boot after a rebuild, the Codex mixin restores its saved index as the agent, before any harness launches, and consumes that backup only after the restore succeeds. It never overwrites an existing index. To restore Git branches, run `lab backup.sh --restore` before you resume work. It keeps the bundles and never checks out or writes shared working files. Histories that were already restored are left alone. The script won't overwrite different later history or staged work. A fresh metadata copy that `git status` initialized is also safe to restore into.

Credentials and harness configuration stay off the state mount, so you need to sign in to Codex again after rebuilding. The mount does not protect against deletion. The agent can change or delete its contents, as with any other writable shared folder.

To keep a room's state somewhere else, create the directory there and symlink `~/.lab/state/<instance>` to it before you create the room. Lab resolves that path at create and at every start. It rejects a path that points into its code, its secrets, the git store, Lima's state, or another room's state. It also rejects user mounts that expose state, relocated directories included. If the directory has disappeared, Lab recreates it empty at start. A dangling symlink has to be repaired first.

An older instance needs `lab rebuild` to get the state mount and transcript links. Save its existing transcripts first, because Lab does not migrate guest-only files.

## Git

Every room protects your git metadata. Running git inside shared projects is optional.

A repo's `.git` folder holds hooks and settings that git runs on its own, so an agent that can write there could plant code that runs on your Mac, as you, the next time you use git. The first time you start a room whose writable folders contain repos, Lab stops and tells you to run `lab harden`. That command moves each repo's `.git` folder to `~/.lab/git` and leaves a small locked file in its place that points there.

Without the `git` mixin, that pointer leads nowhere inside the room. The files are still shared and you can still edit them. Native Git works for repos and clones that live only in the guest, but it cannot see the hardened metadata on your Mac. A tool that requires a Git repo may need its usual override for running outside one.

Run `lab harden` again whenever you clone a new repo into a shared folder. Lab won't start until you do. When you leave the room, Lab checks again and warns you if a `.git` directory or unprotected pointer appeared during the session. Look before you run git there.

The scan covers dependency directories such as `node_modules` and `.venv`, and the git wall applies to them too. An unlocked `.git` file can point at metadata under any name, and a `.git` symlink is not a protected pointer, so Lab flags both. `harden` reports these pointers for you to inspect and does not trust them automatically. If the scan itself fails, launch stops instead of reporting a clean room. These checks guard hardened host metadata. They do not vouch for directories or bare repositories the agent created as safe inputs to host Git.

### Optional Git integration

Select the `git` mixin at create or rebuild to get independent, agent-owned Git metadata against the same shared files. Only then does Lab mount the host store read-only at `/mnt/lab-git`, prepare the guest's metadata root and install its wrapper. Enabling or disabling the mixin takes a rebuild.

The wrapper creates a repo's private metadata copy on its first use, at the path named by the locked pointer. Later boots fetch into that copy on its first use; repos you don't use are left alone. The copy has its own index, objects and configuration, not the host's hooks or remotes. Calling `/usr/bin/git` directly bypasses this convenience sync, not a security wall.

Host branches appear as `origin/main`, `origin/feature`, and so on. The first local branch is `agent`, starting at the host's current HEAD, or unborn if the host repo has no commits. Every local branch is the agent's; `git switch main` does not silently make one from `origin/main`. Ordinary commits, branching and switching work. Fetching changes only remote-tracking refs, never the checked-out branch, its index or the shared files. Host edits therefore appear as unstaged changes against the agent's branch. To restore the host version of a file, use `git restore --source=origin/main -- <file>`.

**The files are shared, not separate checkouts.** Switching a guest branch changes the files on your Mac too. Guest commits and branches stay on the guest's disk; preserve them with `lab backup.sh` before a rebuild and `lab backup.sh --restore` afterward. Publishing still means reviewing and committing the shared files on your Mac. Delivery of guest commits is not built yet. Guest commits use the agent's name and `<agent>@localhost` email.

The host store is readable in the room, so do not embed credentials in repo configuration or hooks. Lab does not import your host's credential manager.

For an older instance, rebuild and select `git` to use the integration. In a new room, run `git status` once in a repo if a harness examines it before making any git call: that creates its metadata copy. Harness-specific directory-trust decisions are still yours.

### Undo hardening

Exit every Lab room first. Then, on your Mac:

```
lab unharden <repo>
lab unharden --all
```

The command unlocks and removes each protected pointer and moves its metadata back into the repo. It won't run while any Lab instance is running. Add `-n` to preview the moves. A linked Git worktree's pointer is not treated as a hardened repo. If Git cannot open a repo after its move, Lab undoes the move for that repo. Metadata copies inside the guest stay as they are until you rebuild.

With `--all`, Lab matches store entries to the repo pointers themselves, not just to their path names. Histories whose repos have moved or disappeared are reported as orphans and left in place. The store defaults to `~/.lab/git`. Set `LAB_GIT_STORE` to use a different one.

## Uninstall

Run `lab uninstall -n` to see the plan, then `lab uninstall`. It asks for confirmation every time, even with `--yes`. Uninstall stops Lab's running rooms, moves the protected metadata of live repos back into them, deletes the instances Lab built, and removes the `~/.lab` entry. If a metadata move fails, deletion stops so you can fix the problem and run it again. Lima and any instances Lab did not build stay in place.

The plan lists what will be deleted and what will be kept: rooms, repo histories, credentials, and each room's persistent state. That state can include transcripts, backups, and delivery bundles you have not fetched. Orphaned histories inside the removed tree are deleted along with it. Save anything you need before you run it.

**Relocation links preserve external targets.** Uninstall removes symlinks and leaves their targets alone, whether a link points to state, secrets, the Git store, or `~/.lab` itself. An external Git store stays after live histories move back to their repos, and its orphan histories stay with it. A dangling data link does not block uninstall. A target inside the deleted tree is deleted with that tree, whatever links point to it. Uninstall has no option to delete relocated contents automatically.

Afterward, remove the `~/.lab/bin` PATH line you added to your shell profile. Lab never edits your profile.

## What Lab protects, and what it doesn't

Inside the room, the agent:

- sees only the folders you shared, plus Lab's guest files (read-only) and its own state (read-write). With the optional Git mixin, it also sees the protected git store, read-only.
- can reach the public internet but not private addresses, such as your home or office network or cloud metadata services.
- runs as its own ordinary user without admin rights.
- can't change the network rules, reach your keys folder or Lima's own files, or write to your Mac's protected git metadata.

What it can still do:

- **Change or delete anything in a folder you shared as writable.** That is why you shared it. Keep those folders under version control, and share a folder read-only when the agent only needs to read it.
- **Send what it can read to the internet.** It has public internet access, so don't share anything that shouldn't leave your Mac.
- **Read its own keys.** Its tools use those keys, so it can see them, as in any other sandbox.

Codex ships its own sandbox, and Lab turns it off because the room already serves as the sandbox. Expect a startup warning that `bwrap` is missing.

## Checking the room

Run `lab verify.sh`. It tests each of the protections above from inside the room and prints one line per test:

```
Network
  ✓ egress     HTTP 200 from example.com
  ✓ private    5 refused, 0 left the guest
  ✓ fence      refused: Operation not permitted (you must be root)
```

✓ passed, ✗ failed. A tally at the end names any failures. Everything each test ran, with its full output, is saved inside the room, in `~/.lab/verify.log`.
