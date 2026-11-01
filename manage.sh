#!/usr/bin/env bash
# bashrc-d-scripts manager.
#
# Usage:
#   manage.sh install [options]     Install/sync on this machine (interactive).
#   manage.sh list                  List modules and their enabled state.
#   manage.sh enable <module>...    Enable module(s) in bashrc.d/enabled/.
#   manage.sh disable <module>...   Disable module(s) in bashrc.d/enabled/.
#   manage.sh enable-all            Enable every module in available/.
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
BLOCK_MARKER="bashrc.d modular config"
BIN_PATH_MARKER="bashrc.d bin PATH entry"

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

Install options:
  --non-interactive        No prompts; all decisions must be flagged.
  --bin-mode MODE          path | symlink-dir | symlink-files | copy | none
  --immutable yes|no       Apply chattr +i protection during install.
  --enable MODULE          Enable a module during install (repeatable).
  --enable-all             Enable every module during install.
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
        printf '' ; return 0
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

# --------------------------------------------------------------------------
# Module commands
# --------------------------------------------------------------------------
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
    local name canonical
    for name in "$@"; do
        canonical="$(resolve_module "$name")" || { warn "Module not found in available/: $name"; continue; }
        if [ -L "$ENABLED_DIR/$canonical" ]; then
            log "Already enabled: $canonical"
        else
            ln -s "../available/$canonical" "$ENABLED_DIR/$canonical"
            log "Enabled: $canonical"
        fi
    done
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
        cmd_enable "$(basename "$f")"
        n=$((n + 1))
    done
    log "Enabled (or already enabled) $n module(s)."
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
# Install
# --------------------------------------------------------------------------
repo_path_literal() {
    case "$REPO_DIR" in
        "$HOME"*) printf '"${HOME}"%s' "${REPO_DIR#"$HOME"}" ;;
        *)        printf '"%s"' "$REPO_DIR" ;;
    esac
}

install_bashrc_block() {
    local block_repo block tmp
    block_repo="$(repo_path_literal)"
    block="# ${BLOCK_MARKER} - generated by manage.sh
BASHRC_D_SCRIPTS_DIR=${block_repo}
if [ -d \"\${BASHRC_D_SCRIPTS_DIR}/bashrc.d/enabled\" ]; then
    for rc in \"\${BASHRC_D_SCRIPTS_DIR}\"/bashrc.d/enabled/*.sh; do
        [ -f \"\$rc\" ] || continue
        . \"\$rc\"
    done
    unset rc
fi
unset BASHRC_D_SCRIPTS_DIR"

    if [ ! -f "$BASHRC" ]; then
        touch "$BASHRC"
        log "Created empty ${BASHRC}"
    elif grep -q "$BLOCK_MARKER" "$BASHRC" 2>/dev/null; then
        tmp="$(mktemp)"
        sed "/# ${BLOCK_MARKER}/,/^unset BASHRC_D_SCRIPTS_DIR$/d" "$BASHRC" > "$tmp"
        { cat "$tmp"; printf '\n%s\n' "$block"; } > "$BASHRC"
        rm -f "$tmp"
        log "Updated existing sourcing block in ${BASHRC}."
        return 0
    else
        cp "$BASHRC" "${BASHRC}.bak"
        log "Backed up ${BASHRC} to ${BASHRC}.bak"
    fi
    printf '\n%s\n' "$block" >> "$BASHRC"
    log "Appended sourcing block to ${BASHRC}."
}

install_bin_mode() {
    local mode="$1" f n skipped block block_repo
    case "$mode" in
        none)
            log "bin/: skipped." ;;
        path)
            block_repo="$(repo_path_literal)"
            block="# ${BIN_PATH_MARKER}
case \":\$PATH:\" in
    *\":${block_repo}/bin:\"*) ;;
    *) export PATH=\"\$PATH:${block_repo}/bin\" ;;
esac"
            if grep -q "$BIN_PATH_MARKER" "$BASHRC" 2>/dev/null; then
                log "bin/: PATH entry already present in ${BASHRC}."
            else
                printf '\n%s\n' "$block" >> "$BASHRC"
                log "bin/: PATH entry appended to ${BASHRC}."
            fi ;;
        symlink-dir)
            mkdir -p "$LOCAL_BIN"
            if [ -e "$LOCAL_BIN/bashrc-d-scripts" ] && [ ! -L "$LOCAL_BIN/bashrc-d-scripts" ]; then
                warn "$LOCAL_BIN/bashrc-d-scripts exists and is not a symlink — skipping."
                return 0
            fi
            ln -sfn "$BIN_DIR" "$LOCAL_BIN/bashrc-d-scripts"
            log "bin/: symlinked directory $LOCAL_BIN/bashrc-d-scripts -> $BIN_DIR." ;;
        symlink-files)
            mkdir -p "$LOCAL_BIN"
            n=0; skipped=0
            for f in "$BIN_DIR"/*; do
                [ -e "$f" ] || continue
                n=$((n + 1))
                if [ -e "$LOCAL_BIN/$(basename "$f")" ] && [ ! -L "$LOCAL_BIN/$(basename "$f")" ]; then
                    warn "Skipping $(basename "$f") — exists in $LOCAL_BIN and is not our symlink."
                    skipped=$((skipped + 1))
                    continue
                fi
                ln -sfn "$f" "$LOCAL_BIN/$(basename "$f")"
            done
            log "bin/: symlinked $n file(s) into $LOCAL_BIN ($skipped skipped)." ;;
        copy)
            mkdir -p "$LOCAL_BIN"
            n=0
            for f in "$BIN_DIR"/*; do
                [ -e "$f" ] || continue
                if [ -e "$LOCAL_BIN/$(basename "$f")" ] && [ ! -L "$LOCAL_BIN/$(basename "$f")" ]; then
                    warn "Skipping $(basename "$f") — exists in $LOCAL_BIN."
                    continue
                fi
                rm -f "$LOCAL_BIN/$(basename "$f")"
                cp "$f" "$LOCAL_BIN/"
                n=$((n + 1))
            done
            log "bin/: copied $n file(s) into $LOCAL_BIN (copies do NOT auto-update; re-run after changes)." ;;
    esac
}

# --------------------------------------------------------------------------
# chattr protection
# --------------------------------------------------------------------------
apply_immutable() {
    local prefix t ok=0 failed=0
    local -a targets=()

    if ! have_sudo; then
        warn "Not root and sudo unavailable — cannot set immutable flags. Skipping."
        return 0
    fi
    prefix="$(sudo_prefix)"

    targets+=("$BASHRC" "$REPO_DIR")
    case "${BIN_MODE:-none}" in
        symlink-dir) targets+=("$LOCAL_BIN/bashrc-d-scripts") ;;
        symlink-files|copy)
            for t in "$LOCAL_BIN"/*; do
                [ -L "$t" ] || targets+=("$t")
            done
            ;;
    esac

    for t in "${targets[@]}"; do
        [ -e "$t" ] || continue
        if $prefix chattr +i "$t" 2>/dev/null; then
            ok=$((ok + 1))
        else
            failed=$((failed + 1))
            warn "Could not set immutable flag on: $t"
        fi
    done
    if [ "$failed" -eq 0 ]; then
        log "Protect: set chattr +i on $ok path(s)."
    else
        warn "Protect: $ok succeeded, $failed failed (unsupported filesystem? permissions?)."
    fi
}

cmd_protect()   { BIN_MODE="${BIN_MODE:-detect}" apply_immutable; }
cmd_unprotect() {
    local prefix t
    if ! have_sudo; then
        warn "Not root and sudo unavailable — cannot remove immutable flags."
        return 0
    fi
    prefix="$(sudo_prefix)"
    for t in "$BASHRC" "$REPO_DIR" "$LOCAL_BIN"/*; do
        [ -e "$t" ] || continue
        $prefix chattr -i "$t" 2>/dev/null || true
    done
    log "Unprotect: removed chattr +i from ~/.bashrc, repo tree, and ~/.local/bin files."
}

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
            printf '  2) symlink-dir — one symlink in ~/.local/bin\n'
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
                cmd_enable "$m"
            fi
        done
    elif [ "$INTERACTIVE" -eq 1 ]; then
        local answer
        printf 'Available modules:\n'
        cmd_list
        read -r -p "Enable modules (space-separated, blank to skip): " answer || answer=""
        local name
        for name in $answer; do cmd_enable "$name"; done
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
    enable)     cmd_enable "$@" ;;
    disable)    cmd_disable "$@" ;;
    enable-all) cmd_enable_all ;;
    protect)    cmd_protect ;;
    unprotect)  cmd_unprotect ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; die "Unknown command: $cmd" ;;
esac
