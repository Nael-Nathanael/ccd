# ccd: multiple Claude Code profiles on one machine

Two Claude subscriptions? Work account and personal account? Hit the limit on
one and want to keep going on the other?

Claude Code only remembers one login. `ccd` gives you as many as you want, and
they all share the same history, settings and projects.

```
ccd 2
```

That's the whole thing. One file of bash, no daemon, no config.

## TL;DR

1. Put `ccd` on your PATH (one command, below).
2. Run `ccd 2`. Type `/login`. Sign in with your second account.
3. From now on: `ccd` is account one, `ccd 2` is account two, `ccd 3` is
   account three.

You log in once per profile. Switching never logs anything out. Run them side by
side in two terminals if you like.

## Install

```
git clone https://github.com/Nael-Nathanael/ccd
install -m 755 ccd/ccd ~/.local/bin/ccd
```

You need `bash` and `claude`. If you have `jq` too, new profiles start with your
MCP servers already set up.

## Use

```
ccd            # profile 1. Same as typing `claude`. Your current setup, untouched.
ccd 2          # profile 2
ccd 3 -p "hi"  # whatever comes after the number is handed to claude
ccd --resume   # no number means profile 1
```

Tired of typing the same flags? Put them in `CCD_ARGS`:

```
export CCD_ARGS="--dangerously-skip-permissions"
```

## What's shared, what isn't

Shared by every profile, because they are symlinks back to `~/.claude`:

projects, conversation history, settings, `CLAUDE.md`, hooks, plugins, skills,
rules, agents, commands.

Separate for each profile:

- The login. That's the point.
- The MCP server list, project trust prompts and first-run state. Claude Code
  keeps these in one file, `.claude.json`, next to the login. A new profile gets
  a copy of your MCP servers when it is created. After that, a server you add in
  one profile has to be added in the others too.

## How it works

Claude Code keeps everything in one folder and lets you move that folder with
the `CLAUDE_CONFIG_DIR` variable. `ccd 2` runs `claude` with that variable set
to `~/.claude-profile-2`.

Before it starts Claude, `ccd` fills the profile folder with symlinks to the
shared things in `~/.claude`. It does this on every start and skips what is
already there, so a folder you create in `~/.claude` next month shows up in
every profile by itself.

Profile 1 gets none of this. `ccd` and `ccd 1` run plain `claude`.

## Remove a profile

```
rm -rf ~/.claude-profile-2
```

That throws away the profile's login and its MCP list. Your history and settings
are symlinks, so they stay where they were, in `~/.claude`.

## Usage limits in your panel

On KDE Plasma?
[claude-limits-plasmoid](https://github.com/Nael-Nathanael/claude-limits-plasmoid)
shows the 5-hour and weekly usage of each profile in the top bar, so you can see
which account still has room.

## License

MIT
