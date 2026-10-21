# ccd: multiple Claude Code profiles on one machine

A work account and a personal account? A client's team plan next to your own?

Claude Code only remembers one login. `ccd` gives each account its own, and
they all share the same history, settings and projects.

```
ccd 2
```

That's the whole thing. One short script per system, no daemon, no config. Works on macOS,
Linux and Windows.

## TL;DR

1. Put `ccd` on your PATH (one command, below).
2. Run `ccd 2`. Type `/login`. Sign in with your second account.
3. From now on: `ccd` is account one, `ccd 2` is account two, `ccd 3` is
   account three.

You log in once per profile. Switching never logs anything out. Run them side by
side in two terminals if you like.

## Is this allowed?

Anthropic's own docs describe this setup:

> To stay signed in to multiple accounts at once, such as work and personal
> accounts, give each account its own configuration directory.

That's from [Log in with multiple accounts](https://code.claude.com/docs/en/authentication)
in the Claude Code docs. `ccd` sets that directory for you. It runs the official
`claude` as is. You sign in through Claude's own `/login`, and `ccd` never
touches your login token.

The usual rules still apply to every account. Each one is yours, so don't share
it or its login with anyone else
([Consumer Terms](https://www.anthropic.com/legal/consumer-terms), section 2).
Plan limits also assume ordinary, individual use
([Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)).

This is a plain reading of Anthropic's public docs, not legal advice.

## Install

`~/.local/bin` is the folder Claude Code's own installer uses, so it is usually
on your PATH already.

### macOS and Linux

In Terminal:

```
git clone https://github.com/Nael-Nathanael/ccd
mkdir -p ~/.local/bin
install -m 755 ccd/ccd ~/.local/bin/ccd
```

You need `claude`. The bash that ships with macOS is fine. If you have `jq` too
(macOS 15 and later include it), new profiles start with your MCP servers
already set up.

### Windows

In PowerShell:

```
git clone https://github.com/Nael-Nathanael/ccd
New-Item -ItemType Directory -Force "$HOME\.local\bin" | Out-Null
Copy-Item ccd\ccd.ps1 "$HOME\.local\bin\"
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

The last line lets PowerShell run scripts you have on disk. Windows blocks them
by default. Skip it if `Get-ExecutionPolicy` already says `RemoteSigned`.

Then turn on **Developer Mode** (Settings, search "developer"). Without it,
Windows won't let `ccd` link `settings.json`, `CLAUDE.md` and `history.jsonl`
into a profile, so those stay separate. `ccd` tells you when that happens.
Folders are shared either way.

Run `ccd` from PowerShell or Windows Terminal. Command Prompt (`cmd`) is not
supported.

## Use

```
ccd            # profile 1. Same as typing `claude`. Your current setup, untouched.
ccd 2          # profile 2
ccd 3 -p "hi"  # whatever comes after the number is handed to claude
ccd --resume   # no number means profile 1
```

Tired of typing the same flags? Put them in `CCD_ARGS`:

```
export CCD_ARGS="--dangerously-skip-permissions"        # macOS, Linux
$env:CCD_ARGS = "--dangerously-skip-permissions"        # Windows PowerShell
```

## What's shared, what isn't

Shared by every profile, because they are links back to `~/.claude`:

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

On Windows, `ccd.ps1` does the same with junctions for folders and symlinks for
files. Junctions are Windows' folder links and need no special rights. The
login is kept per profile on every system, in the macOS Keychain or in the
profile's `.credentials.json`.

Profile 1 gets none of this. `ccd` and `ccd 1` run plain `claude`.

## Remove a profile

macOS and Linux:

```
rm -rf ~/.claude-profile-2
```

Windows: delete the `.claude-profile-2` folder in your user folder with File
Explorer. Explorer removes the links, not what they point to. Avoid
`Remove-Item -Recurse` here: its handling of links
[has had bugs](https://github.com/PowerShell/PowerShell/issues/16664).

That throws away the profile's login and its MCP list. Your history and settings
are links, so they stay where they were, in `~/.claude`.

## Usage limits in your panel

On KDE Plasma?
[claude-limits-plasmoid](https://github.com/Nael-Nathanael/claude-limits-plasmoid)
shows the 5-hour and weekly usage of each profile in the top bar.

## License

MIT
