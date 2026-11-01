# bashrc.d-scripts

A modular `~/.bashrc.d/` framework for bash. Instead of one bloated `~/.bashrc`,
your shell config lives in small, self-contained scripts that are sourced
automatically at startup — the same idea as `/etc/profile.d/`, but for your
home directory.

## Why

A single `~/.bashrc` grows forever: aliases, prompt settings, PATH tweaks,
tool-specific config, one-off hacks. Splitting it into a directory of small
scripts keeps things readable, sortable, and easy to share between machines.

## How it works

Your `~/.bashrc` contains one small block that sources every `*.sh` file in
`~/.bashrc.d/`, in sorted order:

```bash
# ~/.bashrc.d/ modular config
if [ -d "${HOME}/.bashrc.d" ]; then
    for rc in "${HOME}"/.bashrc.d/*.sh; do
        [ -f "$rc" ] && . "$rc"
    done
    unset rc
fi
```

The `*.sh` suffix is intentional: it keeps READMEs, editor backups, and
disabled files out of the glob. To temporarily disable a script, rename it
(e.g. `10-prompt.sh.disabled`).

## File naming convention

Files are sourced in lexical order, so use a numeric prefix to control
dependencies (e.g. environment before prompt):

```
~/.bashrc.d/
├── 00-path.sh          # PATH setup — should come first
├── 10-environment.sh   # exports, editor, misc env vars
├── 20-aliases.sh       # general aliases
├── 30-functions.sh     # helper functions
├── 40-tools.sh         # tool-specific config (nvm, pyenv, direnv, ...)
├── 50-prompt.sh        # prompt/theme — should come last
└── README.md           # not sourced (no .sh suffix)
```

## Installation

### Fresh install (clones this repo into ~/.bashrc.d)

```bash
git clone https://github.com/markcunninghamgit/bashrc-d-scripts.git ~/.bashrc.d
~/.bashrc.d/install.sh
```

`install.sh` backs up your existing `~/.bashrc` to `~/.bashrc.bak` if it needs
to modify it, appends the sourcing block, and does **not** overwrite anything
you already wrote yourself.

### Manual setup

1. Copy or clone this repo's `scripts/` contents into `~/.bashrc.d/`
2. Add the sourcing block (above) to your `~/.bashrc`
3. Restart your shell or run `exec bash`

### Updating

Since the directory is a git clone:

```bash
cd ~/.bashrc.d && git pull
```

Your own scripts stay in the directory alongside the tracked ones — keep local
or machine-specific scripts untracked, or fork the repo and commit them.

## Writing your own scripts

Each script is sourced by your interactive shell, so it has full access to
your environment. Keep them small and single-purpose:

```bash
# ~/.bashrc.d/99-example.sh
alias ll='ls -alF'

greet() {
    printf 'Hello, %s\n' "${USER:-there}"
}
```

Guidelines:

- One concern per file; name it after what it does.
- Guard tool-specific scripts so they don't error when the tool is missing:
  `command -v nvm >/dev/null || return 0`
- Prefix personal scripts with a high number (`90-`+) so they load after the
  framework's environment setup.

## Which files exist here

| File | Purpose |
|---|---|
| `install.sh` | Appends the sourcing block to `~/.bashrc` (with backup) |
| `scripts/00-path.sh` | PATH additions |
| `scripts/10-environment.sh` | Editor, history, and general exports |
| `scripts/20-aliases.sh` | Common aliases |
| `scripts/30-functions.sh` | Small helper functions |
| `scripts/40-tools.sh` | Optional tool integrations (guarded) |
| `scripts/50-prompt.sh` | Prompt setup |

## Uninstall

Remove the sourcing block from your `~/.rc` and delete `~/.bashrc.d/`. Your
original `~/.bashrc` backup (if created) is at `~/.bashrc.bak`.

## Notes

- `~/.bashrc.d/` is a grassroots convention, not an official bash or distro
  feature — but it's widely used and immediately recognizable to anyone
  reading your dotfiles.
- This framework targets bash. zsh users should look at similar approaches
  in their own ecosystem.
