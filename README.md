# bashrc-d-scripts

My personal machine-setup repo. It's public so I can clone it anywhere, but
**this is not a supported project** — it's my config, for my machines. Reuse
anything you like, at your own risk; don't expect docs, issues, or support.

Three kinds of things live here:

| Directory | What it is |
|---|---|
| `bashrc.d/` | Modular shell config, sourced by `~/.bashrc` |
| `bin/` | Scripts that normally live in `~/bin`, on PATH |
| `setup-scripts/` | One-off scripts to set up an environment (run once per machine) |

## bashrc.d: available / enabled

Shell config modules live in `bashrc.d/available/`. Only modules symlinked
into `bashrc.d/enabled/` are actually sourced — the Debian/Apache
`mods-available` / `mods-enabled` pattern:

```
bashrc.d/
├── available/    # every module; source of truth
└── enabled/      # symlinks -> ../available/<name>.sh; only these get sourced
```

Enable/disable a module on a machine:

```bash
cd <repo>/bashrc.d/enabled
ln -s ../available/50-docker.sh .    # enable
rm 50-docker.sh                      # disable
```

Most modules are numbered `50-`; the sourcing glob sorts lexically, so if
something genuinely must run before/after the rest, give it `10-` or `90-`.

To add a module: drop a file in `bashrc.d/available/`, symlink it in
`enabled/` if you want it on, commit. Nothing else needs updating.

## Install

```bash
git clone https://github.com/markcunninghamgit/bashrc-d-scripts.git
cd bashrc-d-scripts
./install.sh
```

`install.sh` is interactive — it asks about each step — or fully scriptable:

```bash
./install.sh --non-interactive --bin-mode path --immutable no
./install.sh --bin-mode symlink-files --enable 50-nvm --enable 50-dotnet
```

It will:

1. Append a sourcing block to `~/.bashrc` (backs up to `~/.bashrc.bak` first;
   re-runs update the block in place rather than duplicating it).
2. Put `bin/` on PATH your way: a PATH entry pointing at the repo, a single
   directory symlink in `~/.local/bin`, per-file symlinks, or copies.
3. Optionally enable extra modules.
4. Optionally set `chattr +i` on `~/.bashrc`, the repo tree, and deployed bin
   files (uses sudo automatically if you're not root).

Run `./install.sh --help` for all flags.

## Setup scripts

One-off, run-once-per-machine scripts in `setup-scripts/`:

- `eternal-history.sh` — protects unlimited bash history: comments out any
  numeric `HISTSIZE`/`HISTFILESIZE` exports in `~/.bashrc` (which would let
  bash truncate the history file), creates `~/.bash_eternal_history`, and
  offers `chattr +a` so no session can ever truncate or overwrite it.

## Syncing changes

The repo is the source of truth. Edit files in the checkout, commit, push,
`git pull` on other machines. `bin/` is always current when installed via
PATH entry, directory symlink, or per-file symlinks; only `copy` mode needs
a re-run of `install.sh` after changes.
