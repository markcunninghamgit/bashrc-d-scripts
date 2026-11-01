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
`mods-available` / `mods-enabled` pattern. **The repo ships with nothing
enabled**; enabling modules is a per-machine action done with `manage.sh`,
so a fresh clone starts clean and you choose what runs where.

Enable/disable modules on a machine:

```bash
./manage.sh list                     # see what's available and what's on
./manage.sh enable 50-docker 50-venv
./manage.sh disable 50-docker
```

(Manual equivalent: `ln -s ../available/50-docker.sh bashrc.d/enabled/` —
the symlinks are local-only, never committed.)

Most modules are numbered `50-`; the sourcing glob sorts lexically, so if
something genuinely must run before/after the rest, give it `10-` or `90-`.

To add a module: drop a file in `bashrc.d/available/`, enable it where
wanted, commit. Nothing else needs updating.

## Install / manage

```bash
git clone https://github.com/markcunninghamgit/bashrc-d-scripts.git
cd bashrc-d-scripts
./manage.sh install
```

`manage.sh` is the single entry point:

| Command | What it does |
|---|---|
| `install` | Interactive install: sourcing block in `~/.bashrc`, bin exposure, module enabling, optional protection |
| `list` | Show modules and enabled state |
| `enable` / `disable` / `enable-all` | Toggle modules (local symlinks) |
| `protect` / `unprotect` | `chattr +i` on `~/.bashrc`, repo tree, deployed bin files (and remove it — needed before git operations that rewrite protected files) |

`install` prompts for anything not supplied as a flag, or runs fully
scripted:

```bash
./manage.sh install --bin-mode path --immutable no
./manage.sh install --non-interactive --bin-mode symlink-files --enable-all
./manage.sh install --yes        # non-interactive, defaults (none/no)
```

Install steps:

1. Append a sourcing block to `~/.bashrc` (backs up to `~/.bashrc.bak` first;
   re-runs update the block in place rather than duplicating it).
2. Put `bin/` on PATH your way: a PATH entry pointing at the repo, a single
   directory symlink in `~/.local/bin`, per-file symlinks, or copies.
3. Enable the modules you want.
4. Optionally set `chattr +i` on `~/.bashrc`, the repo tree, and deployed bin
   files (uses sudo automatically if you're not root).

## Setup scripts

One-off, run-once-per-machine scripts in `setup-scripts/`:

- `eternal-history.sh` — protects unlimited bash history: comments out any
  numeric `HISTSIZE`/`HISTFILESIZE` exports in `~/.bashrc` (which would let
  bash truncate the history file), creates `~/.bash_eternal_history`, and
  offers `chattr +a` so no session can ever truncate or overwrite it.

## Syncing changes

The repo is the source of truth. Edit files in the checkout, commit, push,
`git pull` on other machines, re-run `./manage.sh install` if the sourcing
block or bin deployment needs refreshing. `bin/` is always current when
installed via PATH entry, directory symlink, or per-file symlinks; only
`copy` mode needs a re-run after changes. If files are `chattr +i`
protected, run `./manage.sh unprotect` before `git pull` and `protect`
after.
