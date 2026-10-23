# lab

A walled room for AI agents.

Coding agents like Claude Code and Codex work best when they can run commands freely. Lab gives them a place to do that: a Linux virtual machine on your Mac where the agent can see only the folders you choose, can reach the public internet but not your local or private networks, and has no admin rights. You type `lab`, your agent starts inside the room. When you leave the agent, the room shuts down.

## Requirements

- A Mac with Apple Silicon.
- [Lima](https://lima-vm.io) 2.2.0 or later, which runs the virtual machine.
- `git`.

## Install

Clone this repo into `~/.lab`, and add `~/.lab/bin` to your `PATH` in your shell profile:

```
git clone https://github.com/ndroppo/lab.git ~/.lab
echo 'export PATH="$HOME/.lab/bin:$PATH"' >> ~/.zshrc
```

Then open a new terminal. `~/.lab` is also where Lab keeps your keys and your repos' protected git data.

Never give a room write access to `~/.lab`, or to a folder containing it, such as your home folder. Lab refuses to run if you do: an agent that could edit Lab could change what Lab runs on your Mac.

## First run

`cd` to the folder you want to work in and run `lab`. It asks:

1. **Folders the agent may change.** Your project folders, typically. Each appears inside the room at the same path it has on your Mac.
2. **Folders the agent may only read.** Reference material, say. One can sit inside a writable folder to protect part of it.
3. **Which agents to install.** Claude Code and Codex are offered; say yes to the ones you use. (Lab calls these mixins.)
4. **Which to start by default.** Choose from the mixins you selected. With only one, Lab chooses it without asking; with none, it opens a shell.

Lab shows what it will build and asks you to confirm. The first build downloads an Ubuntu image and installs everything, so it takes a while. Your chosen harness then starts as the agent user, in the folder you started from if you shared it, or in the agent's home folder if you didn't.

Exit the harness to leave. The room shuts down, and the next `lab` starts it again, in about 15 seconds. `lab --shell` opens a login shell instead; type `exit` to leave that.

## Signing in

**Claude Code:** on your Mac, run `claude setup-token`, then save the token it prints as a file named `CLAUDE_CODE_OAUTH_TOKEN` in `~/.lab/secrets/lab/`. The token lasts about a year.

**Codex:** use `lab --shell`, run `codex login` inside the room, and finish in your Mac's browser. The sign-in stays inside the room; rebuilding the room means signing in again.

Each file in `~/.lab/secrets/lab/` becomes an environment variable of the same name inside the room, so any tool that reads its key from the environment can get it the same way. Lab copies them in each time the room starts, so a changed key takes effect at the next `lab`.

One caution for Codex: if it finds an `OPENAI_API_KEY` and you haven't signed in, it uses the key and bills your API account. Leave that key out of a room you use with a ChatGPT plan.

## Day to day

```
lab            start the default harness, creating the room first if needed
lab codex      start codex, if it is one of the instance's mixins
lab --shell    open the agent's login shell instead
lab create     create a room without starting it
lab rebuild    rebuild a room, offering its current answers as defaults
lab harden     protect the git repos in your shared folders (see below)
```

The launch grammar is `lab [lab options] [harness] [-- args...]`. Lab options go before the harness name; everything after `--` goes to the harness unchanged:

```
lab --instance research claude -- --agent researcher
lab -- --version
```

A mixin's name is the command Lab starts. `create`, `rebuild`, and `harden` are reserved for Lab's verbs and cannot be installed as mixins. The harness starts under a login shell, so it receives the same keys as `lab --shell`. Leaving either runs the same shutdown and git exit check.

- **To change the folders or agents,** run `lab rebuild`. It erases everything inside the room and builds it fresh. Your shared folders live on your Mac, so their contents are untouched; what's lost is anything done only inside the room, such as a Codex sign-in.
- **Older instances** have no `LabHarness` and open a shell on a bare `lab`. You can still name an installed harness, such as `lab codex -- --version`. Choosing a persistent default requires rebuilding: the old provisioning does not use `LabHarness`, so Lima will refuse that param if you add it to the existing instance. Rebuild offers the current default back along with the mixins.
- **More than one room:** add `--instance <name>` to any command, for example a separate room for a separate project. Each room has its own folders, agents, and keys, in `~/.lab/secrets/<name>/`. Only one runs at a time.
- **To preview without changing anything,** add `-n`.
- **Other options:** `--yes` accepts every default without asking; `--cpus`, `--memory`, and `--disk` size the virtual machine; `--show` prints the Lima configuration Lab generates. `lab --help` lists them all.

Lab leaves other Lima virtual machines alone. It won't start, rebuild, or delete one it didn't create.

## Git

Git works as usual on your Mac. Inside the room, it can't see your repos.

That's deliberate. A repo's `.git` folder can hold hooks and settings that git runs automatically, so an agent able to write there could plant something that runs on your Mac, as you, the next time you use git. So the first time you start a room with repos in its writable folders, Lab stops and tells you to run `lab harden`. That moves each repo's `.git` folder to `~/.lab/git`, where the room can't reach, and leaves a small locked file in its place pointing there. Git on your Mac follows the pointer; inside the room, it leads nowhere.

Run `lab harden` again whenever you clone a new repo into a shared folder. Lab won't start until you do. When you leave the room, Lab checks again and warns you if a `.git` folder appeared during the session. Look before you run git there.

Since your repos don't look like repos from inside the room, `codex exec` will refuse to run in them unless you pass `--skip-git-repo-check`, as it would anywhere outside a trusted repo.

To undo `harden` for one repo, on your Mac:

```
chflags nouchg <repo>/.git
rm <repo>/.git
mv ~/.lab/git/<repo's path under your home>.git <repo>/.git
```

## What Lab protects, and what it doesn't

Inside the room, the agent:

- sees only the folders you shared, plus Lab's own files, read-only;
- can reach the public internet, but not private addresses: your home or office network, cloud metadata services, and the like;
- runs as its own ordinary user, with no admin rights;
- can't change the network rules or reach your keys folder, your git metadata, or Lima's own files on your Mac.

What it can still do:

- **Change or delete anything in a folder you shared as writable.** That's the point of sharing it. Use version control, and share read-only what the agent only needs to read.
- **Send what it can read to the internet.** It has the public internet, so don't share what shouldn't leave your Mac.
- **Read its own keys.** The agent's tools use those keys, so it can see them, just as in any other sandbox.

Codex has its own sandbox, which Lab turns off: the room is already the sandbox. A startup warning that `bwrap` is missing is expected.

## Checking the room

Use `lab --shell` and run `verify.sh` inside the room. It tests each of the protections above from the inside and prints one line per test:

```
Network
  ✓ egress     HTTP 200 from example.com
  ✓ private    5 refused, 0 left the guest
  ✓ fence      refused: Operation not permitted (you must be root)
```

✓ passed, ✗ failed. A tally at the end names any failures. Everything each test ran, with its full output, is saved inside the room, in `~/.lab/verify.log`.
