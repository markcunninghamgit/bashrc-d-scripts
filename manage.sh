#!/usr/bin/env bash
# bashrc-d-scripts manager.
#
# Usage:
#   manage.sh install [options]     Install/sync on this machine (interactive).
#   manage.sh list                  List modules and their enabled state.
#   manage.sh enable <module>...    Enable module(s) in bashrc.d/enabled/.
#   manage.sh disable <module>...   Disable module(s) in bashrc.d/enabled/.
#   manage.sh enable-all            Enable every module in bashrc.d/available/.
#   manage.sh protect               Apply chattr +i to ~/.bashrc, repo, bin.
#   manage.sh unprotect             Remove chattr +i (needed before git ops).
#
# install options (all optional; prompts for anything not supplied):
#   --non-interactive               No prompts; every decision must be flagged.
#   --bin-mode path|symlink-dir|symlink-files|copy|none
#                                   How to expose bin/ scripts on PATH.
#   --immutable yes|no              chattr +i protection as part of install.
#   --enable <module> / --enable-all
#                                   Enable modules during install.
#   --force                         Bypass the bash -n syntax check.
#   --yes                           Non-interactive install with defaults
#                                   (bin-mode none, no immutability).
#
# Module commands work directly on the checkout — enable/disable can be run
# any time (they don't touch ~/.bashrc; changes apply on next shell).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="${HOME}/.bashrc"
AVAILABLE_DIR="${REPO_DIR}/bashrc.d/available"
ENABLED_DIR="${REPO_DIR}/bashrc.d/enabled"
BIN_DIR="${REPO_DIR}/bin"
LOCAL_BIN="${HOME}/.local/bin"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/bashrc-d-scripts"
COPIES_STATE="${STATE_DIR}/bin-copies"
BLOCK_MARKER="bashrc.d modular config"
BLOCK_END_RE='^(unset BASHRC_D_SCRIPTS_DIR|unset rc)$'
BIN_PATH_MARKER="bashrc.d bin PATH entry"
BIN_PATH_END_RE='^unset BASHRC_D_SCRIPTS_BIN$'
FORCE=0

usage() {
    cat <<'USAGE'
Usage: manage.sh <command> [options]

Commands:
  install                  Install/sync on this machine (interactive).
  list                     List modules and their enabled state.
  enable <module>...       Enable module(s).
  disable <module>...      Disable module(s).
  enable-all               Enable every module in available/.
  protect                  chattr +i ~/.bashrc, repo tree, deployed bin files.
  unprotect                Remove chattr +i flags.

Module options (enable / enable-all):
  --force                  Bypass the bash -n syntax check when enabling.

Install options:
  --non-interactive        No prompts; all decisions must be flagged.
  --bin-mode MODE          path | symlink-dir | symlink-files | copy | none
  --immutable yes|no       Apply chattr +i protection during install.
  --enable MODULE          Enable a module during install (repeatable).
  --enable-all             Enable every module during install.
  --force                  Enable modules that fail the syntax check.
  --yes                    Non-interactive with defaults (none/no).

Examples:
  manage.sh list
  manage.sh enable 50-docker 50-venv
  manage.sh install --bin-mode path --immutable no
  manage.sh install --non-interactive --bin-mode symlink-files --enable-all
  manage.sh protect
USAGE
}

log()  { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

# --- sudo helper for chattr -------------------------------------------------
have_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    command -v sudo >/dev/null 2>&1
}

sudo_prefix() {
    if [ "$(id -u)" -eq 0 ]; then
        printf ''
    else
        printf 'sudo'
    fi
}

# --- deployed-copies state -------------------------------------------------
# Only copy-mode deployments need recording: symlinks identify themselves by
# resolving into $BIN_DIR. One basename per line.
copies_state_load() {
    [ -f "$COPIES_STATE" ] && cat "$COPIES_STATE" || true
}

copy_is_ours() {
    # copy_is_ours <basename>
    [ -f "$COPIES_STATE" ] && grep -qxF "$1" "$COPIES_STATE"
}

copies_state_add() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$1" >> "$COPIES_STATE"
}

# --------------------------------------------------------------------------
# ~/.bashrc block management
# --------------------------------------------------------------------------
# ensure_block <file> <start_marker_regex> <end_marker_regex> <block-text>
# Replaces the marked block in place if a recognizable terminator exists;
# refuses to delete anything if the marker exists without a terminator
# (e.g. an old format) and appends instead. Always backs up before writing.
ensure_block() {
    local file="$1" start_re="$2" end_re="$3" block="$4" tmp
    if ! grep -qE "$start_re" "$file" 2>/dev/null; then
        if [ -f "$file" ]; then
            cp "$file" "${file}.bak"
        else
            touch "$file"
        fi
        printf '\n%s\n' "$block" >> "$file"
        return 0
    fi

    if ! awk -v s="$start_re" -v e="$end_re" '
            $0 ~ s { inb = 1; next }
            inb && $0 ~ e { found = 1; exit }
            END { exit(found ? 0 : 1) }
        ' "$file"; then
        cp "$file" "${file}.bak"
        warn "Found ${start_re} marker in ${file} but no recognized block terminator."
        warn "Leaving existing lines untouched and appending a fresh block —"
        warn "review ${file}.bak and remove the old block manually if it is obsolete."
        printf '\n%s\n' "$block" >> "$file"
        return 0
    fi

    cp "$file" "${file}.bak"
    tmp="$(mktemp)"
    awk -v s="$start_re" -v e="$end_re" '
        $0 ~ s { inb = 1 }
        inb && $0 ~ e { inb = 0; next }
        !inb { print }
    ' "$file" > "$tmp"
    { cat "$tmp"; printf '\n%s\n' "$block"; } > "$file"
    rm -f "$tmp"
    return 0
}

make_sourcing_block() {
    local dir_q
    dir_q="$(printf '%q' "$REPO_DIR")"
    printf '# %s - generated by manage.sh\nBASHRC_D_SCRIPTS_DIR=%s\nif [ -d "${BASHRC_D_SCRIPTS_DIR}/bashrc.d/enabled" ]; then\n    for rc in "${BASHRC_D_SCRIPTS_DIR}"/bashrc.d/enabled/*.sh; do\n        [ -f "$rc" ] || continue\n        . "$rc"\n    done\n    unset rc\nfi\nunset BASHRC_D_SCRIPTS_DIR' \
        "$BLOCK_MARKER" "$dir_q"
}

make_path_block() {
    # make_path_block <dir>
    local dir_q
    dir_q="$(printf '%q' "$1")"
    printf '# %s - generated by manage.sh\nBASHRC_D_SCRIPTS_BIN=%s\nif ! [[ ":$PATH:" == *":$BASHRC_D_SCRIPTS_BIN:"* ]]; then\n    export PATH="$PATH:$BASHRC_D_SCRIPTS_BIN"\nfi\nunset BASHRC_D_SCRIPTS_BIN' \
        "$BIN_PATH_MARKER" "$dir_q"
}

install_bashrc_block() {
    ensure_block "$BASHRC" "# ${BLOCK_MARKER}" "$BLOCK_END_RE" "$(make_sourcing_block)"
    log "Sourcing block up to date in ${BASHRC}."
}

# --------------------------------------------------------------------------
# Module commands
# --------------------------------------------------------------------------
confirm_syntax() {
    # confirm_syntax <file> <canonical>: returns 0 if OK to enable.
    local file="$1" canonical="$2" err answer
    if err="$(bash -n "$file" 2>&1)"; then
        return 0
    fi
    warn "${canonical} fails bash -n syntax check:"
    printf '  %s\n' "$err" >&2
    if [ "$FORCE" -eq 1 ]; then
        warn "Enabling anyway (--force)."
        return 0
    fi
    if [ -t 0 ] && [ -t 1 ]; then
        while true; do
            read -r -p "Enable ${canonical} anyway? [y/N] " answer || answer=n
            case "${answer:-n}" in
                [Yy]*) return 0 ;;
                [Nn]*|'') return 1 ;;
                *) warn "Please answer yes or no." ;;
            esac
        done
    fi
    warn "Non-interactive with no --force — skipping ${canonical}."
    return 1
}

resolve_module() {
    # resolve_module <name> -> echoes canonical basename, or fails.
    local name="$1" src
    for src in "$AVAILABLE_DIR"/*; do
        [ -e "$src" ] || continue
        if [ "$(basename "$src")" = "$name" ] || [ "$(basename "${src%.sh}")" = "$name" ]; then
            basename "$src"
            return 0
        fi
    done
    return 1
}

cmd_enable() {
    [ $# -ge 1 ] || die "enable: provide one or more module names (see: manage.sh list)"
    local name canonical failed=0
    for name in "$@"; do
        canonical="$(resolve_module "$name")" || { warn "Module not found in available/: $name"; failed=1; continue; }
        if [ -L "$ENABLED_DIR/$canonical" ]; then
            log "Already enabled: $canonical"
            continue
        fi
        if ! confirm_syntax "$AVAILABLE_DIR/$canonical" "$canonical"; then
            failed=1
            continue
        fi
        ln -s "../available/$canonical" "$ENABLED_DIR/$canonical"
        log "Enabled: $canonical"
    done
    [ "$failed" -eq 0 ]
}

cmd_disable() {
    [ $# -ge 1 ] || die "disable: provide one or more module names (see: manage.sh list)"
    local name canonical
    for name in "$@"; do
        canonical="$(resolve_module "$name")" || { warn "Module not found in available/: $name"; continue; }
        if [ -L "$ENABLED_DIR/$canonical" ]; then
            rm "$ENABLED_DIR/$canonical"
            log "Disabled: $canonical"
        elif [ -e "$ENABLED_DIR/$canonical" ]; then
            warn "enabled/$canonical exists but is not a symlink — remove it manually."
        else
            log "Not enabled: $canonical"
        fi
    done
}

cmd_enable_all() {
    local f n=0
    for f in "$AVAILABLE_DIR"/*; do
        [ -e "$f" ] || continue
        cmd_enable "$(basename "$f")" || true
        n=$((n + 1))
    done
    log "Processed $n module(s)."
}

cmd_list() {
    local f enabled_count=0 available_count=0
    printf 'Available modules (%s):\n' "$AVAILABLE_DIR"
    for f in "$AVAILABLE_DIR"/*; do
        [ -e "$f" ] || continue
        available_count=$((available_count + 1))
        if [ -e "$ENABLED_DIR/$(basename "$f")" ]; then
            printf '  [enabled]   %s\n' "$(basename "$f")"
            enabled_count=$((enabled_count + 1))
        else
            printf '  [disabled]  %s\n' "$(basename "$f")"
        fi
    done
    printf '\n%d module(s), %d enabled.\n' "$available_count" "$enabled_count"
}

# --------------------------------------------------------------------------
# bin/ deployment
# --------------------------------------------------------------------------
# bin deployment is detected at runtime (protect/unprotect and copy reruns
# must work without knowing which mode install used):
#   - symlink-dir:  $LOCAL_BIN/bashrc-d-scripts -> $BIN_DIR
#   - symlink-files: symlinks in $LOCAL_BIN resolving into $BIN_DIR
#   - copy:          basenames recorded in $COPIES_STATE
deployed_symlink_files() {
    local f target
    [ -d "$LOCAL_BIN" ] || return 0
    for f in "$LOCAL_BIN"/*; do
        [ -L "$f" ] || continue
        target="$(readlink "$f")" || continue
        case "$target" in
            "$BIN_DIR"/*) basename "$f" ;;
        esac
    done
}

is_deployed_copy() {
    # is_deployed_copy <path> : a copy we own (recorded), not an unrelated file
    copy_is_ours "$(basename "$1")"
}

install_bin_mode() {
    local mode="$1" f n skipped name
    case "$mode" in
        none)
            log "bin/: skipped." ;;
        path)
            ensure_block "$BASHRC" "# ${BIN_PATH_MARKER}" "$BIN_PATH_END_RE" "$(make_path_block "${REPO_DIR}/bin")"
            log "bin/: PATH entry (repo/bin) up to date in ${BASHRC}." ;;
        symlink-dir)
            mkdir -p "$LOCAL_BIN"
            if [ -e "$LOCAL_BIN/bashrc-d-scripts" ] && [ ! -L "$LOCAL_BIN/bashrc-d-scripts" ]; then
                warn "$LOCAL_BIN/bashrc-d-scripts exists and is not a symlink — skipping."
                return 0
            fi
            ln -sfn "$BIN_DIR" "$LOCAL_BIN/bashrc-d-scripts"
            # A directory symlink is not searched by PATH, so expose the
            # directory itself on PATH as well.
            ensure_block "$BASHRC" "# ${BIN_PATH_MARKER}" "$BIN_PATH_END_RE" "$(make_path_block "${LOCAL_BIN}/bashrc-d-scripts")"
            log "bin/: symlinked directory $LOCAL_BIN/bashrc-d-scripts -> $BIN_DIR and added it to PATH." ;;
        symlink-files)
            mkdir -p "$LOCAL_BIN"
            n=0; skipped=0
            for f in "$BIN_DIR"/*; do
                [ -e "$f" ] || continue
                n=$((n + 1))
                name="$(basename "$f")"
                if [ -e "$LOCAL_BIN/$name" ] && [ ! -L "$LOCAL_BIN/$name" ]; then
                    if is_deployed_copy "$LOCAL_BIN/$name"; then
                        rm -f "$LOCAL_BIN/$name"
                    else
                        warn "Skipping $name — exists in $LOCAL_BIN and is not ours."
                        skipped=$((skipped + 1))
                        continue
                    fi
                fi
                ln -sfn "$f" "$LOCAL_BIN/$name"
            done
            log "bin/: symlinked $n file(s) into $LOCAL_BIN ($skipped skipped)." ;;
        copy)
            mkdir -p "$LOCAL_BIN"
            n=0; skipped=0
            for f in "$BIN_DIR"/*; do
                [ -e "$f" ] || continue
                name="$(basename "$f")"
                if [ -e "$LOCAL_BIN/$name" ] && [ ! -L "$LOCAL_BIN/$name" ] && ! is_deployed_copy "$LOCAL_BIN/$name"; then
                    warn "Skipping $name — exists in $LOCAL_BIN and is not ours."
                    skipped=$((skipped + 1))
                    continue
                fi
                rm -f "$LOCAL_BIN/$name"
                cp "$f" "$LOCAL_BIN/$name"
                copies_state_add "$name"
                n=$((n + 1))
            done
            log "bin/: copied $n file(s) into $LOCAL_BIN ($skipped skipped; copies do NOT auto-update — rerun to refresh)." ;;
    esac
}

# --------------------------------------------------------------------------
# chattr protection
# --------------------------------------------------------------------------
collect_protection_targets() {
    # Echoes paths this manager owns: ~/.bashrc, repo tree, deployed bin items.
    local name
    printf '%s\n%s\n' "$BASHRC" "$REPO_DIR"
    [ -L "$LOCAL_BIN/bashrc-d-scripts" ] && printf '%s\n' "$LOCAL_BIN/bashrc-d-scripts"
    for name in $(deployed_symlink_files); do
        printf '%s\n' "$LOCAL_BIN/$name"
    done
    while IFS= read -r name; do
        [ -n "$name" ] && [ -e "$LOCAL_BIN/$name" ] && printf '%s\n' "$LOCAL_BIN/$name"
    done < <(copies_state_load)
}

apply_immutable() {
    local prefix t out ok=0 failed=0
    if ! have_sudo; then
        warn "Not root and sudo unavailable — cannot set immutable flags. Skipping."
        return 0
    fi
    prefix="$(sudo_prefix)"

    while IFS= read -r t; do
        [ -e "$t" ] || continue
        if out="$($prefix find "$t" -exec chattr +i {} + 2>&1)"; then
            ok=$((ok + 1))
        else
            failed=$((failed + 1))
            warn "Could not set immutable flags on: $t"
            [ -n "$out" ] && printf '  %s\n' "$out" >&2
        fi
    done < <(collect_protection_targets)

    if [ "$failed" -eq 0 ]; then
        log "Protect: applied chattr +i recursively to $ok path(s)."
    else
        warn "Protect: $ok succeeded, $failed failed (unsupported filesystem? permissions?)."
    fi
}

cmd_protect()   { apply_immutable; }
cmd_unprotect() {
    local prefix t out
    if ! have_sudo; then
        warn "Not root and sudo unavailable — cannot remove immutable flags."
        return 0
    fi
    prefix="$(sudo_prefix)"
    while IFS= read -r t; do
        [ -e "$t" ] || continue
        $prefix find "$t" -exec chattr -i {} + 2>/dev/null || \
            warn "Could not fully clear immutable flags on: $t"
    done < <(collect_protection_targets)
    log "Unprotect: cleared chattr +i from ~/.bashrc, the repo tree, and deployed bin files."
}

# --------------------------------------------------------------------------
# Install
# --------------------------------------------------------------------------
cmd_install() {
    local INTERACTIVE=1 BIN_MODE="" IMMUTABLE="" ENABLE_LIST=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --non-interactive) INTERACTIVE=0 ;;
            --yes) INTERACTIVE=0; BIN_MODE="${BIN_MODE:-none}"; IMMUTABLE="${IMMUTABLE:-no}" ;;
            --bin-mode)
                [ $# -ge 2 ] || die "--bin-mode requires a value"
                case "$2" in
                    path|symlink-dir|symlink-files|copy|none) BIN_MODE="$2" ;;
                    *) die "--bin-mode must be one of: path, symlink-dir, symlink-files, copy, none" ;;
                esac
                shift ;;
            --immutable)
                [ $# -ge 2 ] || die "--immutable requires a value (yes|no)"
                case "$2" in
                    yes|no) IMMUTABLE="$2" ;;
                    *) die "--immutable must be yes or no" ;;
                esac
                shift ;;
            --enable)
                [ $# -ge 2 ] || die "--enable requires a module name"
                ENABLE_LIST+=("$2"); shift ;;
            --enable-all) ENABLE_LIST+=("__ALL__") ;;
            --force) FORCE=1 ;;
            *) die "Unknown install option: $1 (see: manage.sh with no args)" ;;
        esac
        shift
    done

    [ -d "$AVAILABLE_DIR" ] || die "bashrc.d/available not found under $REPO_DIR"

    log "Repo checkout: $REPO_DIR"

    install_bashrc_block

    # bin mode
    if [ -z "$BIN_MODE" ]; then
        if [ "$INTERACTIVE" -eq 1 ]; then
            local choice
            choice=""
            printf 'How should bin/ scripts be exposed on this machine?\n'
            printf '  1) path — add <repo>/bin to PATH in .bashrc (always in sync)\n'
            printf '  2) symlink-dir — one symlink in ~/.local/bin, directory put on PATH\n'
            printf '  3) symlink-files — symlink each script into ~/.local/bin\n'
            printf '  4) copy — copy scripts into ~/.local/bin (not auto-updated)\n'
            printf '  5) none — skip\n'
            while true; do
                read -r -p "Choice [1]: " choice || choice=1
                choice="${choice:-1}"
                case "$choice" in
                    1|2|3|4|5) break ;;
                    *) warn "Invalid choice." ;;
                esac
            done
            case "$choice" in
                1) BIN_MODE="path" ;;
                2) BIN_MODE="symlink-dir" ;;
                3) BIN_MODE="symlink-files" ;;
                4) BIN_MODE="copy" ;;
                5) BIN_MODE="none" ;;
            esac
        else
            die "--non-interactive requires --bin-mode (or --yes)"
        fi
    fi
    install_bin_mode "$BIN_MODE"

    # module enabling
    if [ ${#ENABLE_LIST[@]} -gt 0 ]; then
        local m
        for m in "${ENABLE_LIST[@]}"; do
            if [ "$m" = "__ALL__" ]; then
                cmd_enable_all
            else
                cmd_enable "$m" || true
            fi
        done
    elif [ "$INTERACTIVE" -eq 1 ]; then
        local answer
        printf 'Available modules:\n'
        cmd_list
        read -r -p "Enable modules (space-separated, blank to skip): " answer || answer=""
        local name
        for name in $answer; do cmd_enable "$name" || true; done
    fi

    # immutability
    if [ -z "$IMMUTABLE" ]; then
        if [ "$INTERACTIVE" -eq 1 ]; then
            local yn
            read -r -p "Apply chattr +i protection to ~/.bashrc, repo tree, and deployed bin files? [y/N] " yn || yn=n
            case "${yn:-n}" in
                [Yy]*) IMMUTABLE="yes" ;;
                *)     IMMUTABLE="no" ;;
            esac
        else
            die "--non-interactive requires --immutable (or --yes)"
        fi
    fi
    if [ "$IMMUTABLE" = "yes" ]; then
        apply_immutable
    else
        log "Protect: skipped."
    fi

    log ""
    log "Done. Restart your shell or run: exec bash"
}

# --------------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------------
[ $# -ge 1 ] || { usage; exit 0; }

cmd="$1"; shift
case "$cmd" in
    install)    cmd_install "$@" ;;
    list)       cmd_list ;;
    enable)
        for arg in "$@"; do
            [ "$arg" = "--force" ] && { FORCE=1; shift; } || break
        done
        cmd_enable "$@" ;;
    disable)    cmd_disable "$@" ;;
    enable-all)
        [ "${1:-}" = "--force" ] && FORCE=1
        cmd_enable_all ;;
    protect)    cmd_protect ;;
    unprotect)  cmd_unprotect ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; die "Unknown command: $cmd" ;;
esac
