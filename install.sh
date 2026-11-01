#!/usr/bin/env bash
# bashrc-d-scripts installer.
#
# Interactive by default; fully scriptable with flags (no positional args):
#   install.sh [--non-interactive]
#              [--bin-mode path|symlink-dir|symlink-files|copy|none]
#              [--immutable yes|no]
#              [--enable <module>] [--enable-all]
#
# Steps:
#   1. Append the bashrc.d sourcing block to ~/.bashrc (with backup, idempotent).
#   2. Expose bin/ scripts according to --bin-mode.
#   3. Optionally enable additional bashrc.d modules (symlinks in enabled/).
#   4. Optionally apply chattr +i immutability to ~/.bashrc, the repo tree,
#      and (for copy/symlink modes) the deployed bin files.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="${HOME}/.bashrc"
AVAILABLE_DIR="${REPO_DIR}/bashrc.d/available"
ENABLED_DIR="${REPO_DIR}/bashrc.d/enabled"
BIN_DIR="${REPO_DIR}/bin"
LOCAL_BIN="${HOME}/.local/bin"
BLOCK_MARKER="bashrc.d modular config"
BIN_PATH_MARKER="bashrc.d bin PATH entry"

INTERACTIVE=1
BIN_MODE=""
IMMUTABLE=""
ENABLE_LIST=()

usage() {
    cat <<'USAGE'
Usage: install.sh [OPTIONS]

Options:
  --non-interactive       Run without prompting; every decision must be
                          supplied via the flags below.
  --bin-mode MODE         How to expose bin/ scripts:
                            path           add <repo>/bin to PATH (in .bashrc)
                            symlink-dir    one symlink ~/.local/bin/bashrc-d-scripts -> <repo>/bin
                            symlink-files  symlink each bin/* into ~/.local/bin
                            copy           copy bin/* into ~/.local/bin
                            none           skip
  --immutable yes|no      chattr +i ~/.bashrc, the repo tree, and deployed
                          bin files (sudo is used automatically if not root).
  --enable MODULE         Enable an additional bashrc.d module (name as it
                          appears in bashrc.d/available/). Repeatable.
  --enable-all            Enable every module in bashrc.d/available/.
  -h, --help              Show this help.
USAGE
}

log()  { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

prompt_yes_no() {
    # prompt_yes_no <question> <default yes|no>
    local question="$1" default="${2:-yes}" answer
    [ "$INTERACTIVE" -eq 1 ] || die "--non-interactive: cannot prompt: $question"
    while true; do
        if [ "$default" = "yes" ]; then
            read -r -p "$question [Y/n] " answer || answer="$default"
        else
            read -r -p "$question [y/N] " answer || answer="$default"
        fi
        case "${answer:-$default}" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) warn "Please answer yes or no." ;;
        esac
    done
}

prompt_choice() {
    # prompt_choice <variable> <question> <option>...
    local __var="$1" question="$2"; shift 2
    local options=("$@") i choice
    [ "$INTERACTIVE" -eq 1 ] || die "--non-interactive: cannot prompt: $question"
    while true; do
        printf '%s\n' "$question"
        i=1
        for opt in "${options[@]}"; do
            printf '  %d) %s\n' "$i" "$opt"
            i=$((i + 1))
        done
        read -r -p "Choice [1]: " choice || choice=1
        choice="${choice:-1}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            printf -v "$__var" '%s' "$choice"
            return 0
        fi
        warn "Invalid choice."
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --non-interactive) INTERACTIVE=0 ;;
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
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
    shift
done

[ -d "$AVAILABLE_DIR" ] || die "bashrc.d/available not found under $REPO_DIR"

# Render the repo path with $HOME collapsed so the block stays valid
# if the whole home dir is identical across machines.
repo_path_literal() {
    case "$REPO_DIR" in
        "$HOME"*) printf '"${HOME}"%s' "${REPO_DIR#"$HOME"}" ;;
        *)        printf '"%s"' "$REPO_DIR" ;;
    esac
}

# --------------------------------------------------------------------------
# 1. bashrc sourcing block
# --------------------------------------------------------------------------
install_bashrc_block() {
    local block_repo block
    block_repo="$(repo_path_literal)"
    block="# ${BLOCK_MARKER} - generated by install.sh
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
        # Refresh the block in place so repo moves are picked up on re-run.
        local tmp
        tmp="$(mktemp)"
        sed "/# ${BLOCK_MARKER}/,/^unset BASHRC_D_SCRIPTS_DIR$/d" "$BASHRC" > "$tmp"
        { cat "$tmp"; printf '\n%s\n' "$block"; } > "$BASHRC"
        rm -f "$tmp"
        log "Updated existing sourcing block in ${BASHRC} (backup at ${BASHRC}.bak)."
        cp "$BASHRC" "${BASHRC}.latest" 2>/dev/null || true
        return 0
    else
        cp "$BASHRC" "${BASHRC}.bak"
        log "Backed up ${BASHRC} to ${BASHRC}.bak"
    fi
    printf '\n%s\n' "$block" >> "$BASHRC"
    log "Appended sourcing block to ${BASHRC}."
}

# --------------------------------------------------------------------------
# 2. bin/ exposure
# --------------------------------------------------------------------------
install_bin_mode() {
    local mode="$1" f n skipped
    case "$mode" in
        none)
            log "bin/: skipped." ;;
        path)
            local block_repo block
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
# 3. module enabling
# --------------------------------------------------------------------------
enable_module() {
    local module="$1" src dst
    for src in "$AVAILABLE_DIR"/*; do
        [ -e "$src" ] || continue
        if [ "$(basename "$src")" = "$module" ] || [ "$(basename "${src%.sh}")" = "$module" ]; then
            dst="$ENABLED_DIR/$(basename "$src")"
            if [ -L "$dst" ]; then
                log "Module already enabled: $(basename "$src")"
            else
                ln -s "available/$(basename "$src")" "$dst"
                log "Enabled module: $(basename "$src")"
            fi
            return 0
        fi
    done
    warn "Module not found in available/: $module"
    return 1
}

enable_modules() {
    local m f name picks available=()
    if [ ${#ENABLE_LIST[@]} -eq 0 ]; then
        [ "$INTERACTIVE" -eq 1 ] || return 0
        prompt_yes_no "Enable additional bashrc.d modules (beyond committed enabled/ symlinks)?" "no" || return 0
        for f in "$AVAILABLE_DIR"/*; do
            [ -e "$f" ] && available+=("$(basename "$f")")
        done
        if [ ${#available[@]} -gt 0 ]; then
            printf 'Available modules:\n'
            printf '  %s\n' "${available[@]}"
            read -r -p "Module names (space-separated, blank to skip): " picks || picks=""
            for name in $picks; do enable_module "$name"; done
        fi
        return 0
    fi
    for m in "${ENABLE_LIST[@]}"; do
        if [ "$m" = "__ALL__" ]; then
            for f in "$AVAILABLE_DIR"/*; do
                [ -e "$f" ] && enable_module "$(basename "$f")"
            done
        else
            enable_module "$m"
        fi
    done
}

# --------------------------------------------------------------------------
# 4. immutability
# --------------------------------------------------------------------------
apply_immutable() {
    local sudo_cmd="" t ok=0 failed=0
    local -a targets=()

    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo_cmd="sudo"
        else
            warn "Not root and sudo unavailable — cannot set immutable flags. Skipping."
            return 0
        fi
    fi

    targets+=("$BASHRC" "$REPO_DIR")
    case "$BIN_MODE" in
        symlink-dir) targets+=("$LOCAL_BIN/bashrc-d-scripts") ;;
        symlink-files|copy)
            for t in "$LOCAL_BIN"/*; do
                [ -L "$t" ] || targets+=("$t")
            done
            ;;
    esac

    for t in "${targets[@]}"; do
        [ -e "$t" ] || continue
        if $sudo_cmd chattr +i "$t" 2>/dev/null; then
            ok=$((ok + 1))
        else
            failed=$((failed + 1))
            warn "Could not set immutable flag on: $t"
        fi
    done
    if [ "$failed" -eq 0 ]; then
        log "Immutability: set chattr +i on $ok path(s)."
        log "Note: run 'sudo chattr -i <path>' before git operations that rewrite these files."
    else
        warn "Immutability: $ok succeeded, $failed failed (unsupported filesystem? permissions?)."
    fi
}

# --------------------------------------------------------------------------
# Main flow
# --------------------------------------------------------------------------
log "Repo checkout: $REPO_DIR"

install_bashrc_block

if [ -z "$BIN_MODE" ]; then
    if [ "$INTERACTIVE" -eq 1 ]; then
        choice=""
        prompt_choice choice \
            "How should bin/ scripts be exposed on this machine?" \
            "path — add <repo>/bin to PATH in .bashrc (always in sync)" \
            "symlink-dir — one symlink in ~/.local/bin" \
            "symlink-files — symlink each script into ~/.local/bin" \
            "copy — copy scripts into ~/.local/bin (not auto-updated)" \
            "none — skip"
        case "$choice" in
            1) BIN_MODE="path" ;;
            2) BIN_MODE="symlink-dir" ;;
            3) BIN_MODE="symlink-files" ;;
            4) BIN_MODE="copy" ;;
            5) BIN_MODE="none" ;;
        esac
    else
        die "--non-interactive requires --bin-mode"
    fi
fi
install_bin_mode "$BIN_MODE"

enable_modules

if [ -z "$IMMUTABLE" ]; then
    if [ "$INTERACTIVE" -eq 1 ]; then
        if prompt_yes_no "Apply chattr +i immutability to ~/.bashrc, the repo tree, and deployed bin files?" "no"; then
            IMMUTABLE="yes"
        else
            IMMUTABLE="no"
        fi
    else
        die "--non-interactive requires --immutable"
    fi
fi
if [ "$IMMUTABLE" = "yes" ]; then
    apply_immutable
else
    log "Immutability: skipped."
fi

log ""
log "Done. Restart your shell or run: exec bash"
