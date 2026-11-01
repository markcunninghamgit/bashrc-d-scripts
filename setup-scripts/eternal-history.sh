#!/usr/bin/env bash
# setup-scripts/eternal-history.sh
#
# One-off setup for the "eternal bash history" module
# (bashrc.d/available/50-eternal-history.sh).
#
#   1. Backs up ~/.bashrc.
#   2. Comments out any `export HISTFILESIZE=<number>` / `export HISTSIZE=<number>`
#      lines in ~/.bashrc — a later numeric value would let bash truncate the
#      eternal history file. Empty-value exports (the eternal-history style)
#      are left alone.
#   3. Creates ~/.bash_eternal_history if missing.
#   4. Offers to set chattr +a (append-only) on ~/.bash_eternal_history so no
#      bash session can truncate or overwrite it.
#
# Usage: setup-scripts/eternal-history.sh [--yes]

set -euo pipefail

BASHRC="${HOME}/.bashrc"
HISTFILE_ETERNAL="${HOME}/.bash_eternal_history"
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --yes) ASSUME_YES=1 ;;
        -h|--help)
            printf 'Usage: %s [--yes]\n' "$0"
            exit 0 ;;
        *) printf 'Error: unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

log()  { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }

yes_no() {
    local question="$1" answer
    if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
    while true; do
        read -r -p "$question [y/N] " answer || return 1
        case "${answer:-n}" in
            [Yy]* ) return 0 ;;
            [Nn]* | "" ) return 1 ;;
            * ) warn "Please answer yes or no." ;;
        esac
    done
}

# --------------------------------------------------------------------------
# 1. Backup
# --------------------------------------------------------------------------
if [ -f "$BASHRC" ]; then
    cp "$BASHRC" "${BASHRC}.bak"
    log "Backed up ${BASHRC} to ${BASHRC}.bak"
else
    touch "$BASHRC"
    log "Created empty ${BASHRC}"
fi

# --------------------------------------------------------------------------
# 2. Comment out numeric HISTSIZE / HISTFILESIZE exports
# --------------------------------------------------------------------------
changed=0
if grep -Eq '^[[:space:]]*export[[:space:]]+HIST(FILE)?SIZE[[:space:]]*=[[:space:]]*[0-9]+' "$BASHRC"; then
    sed -i -E 's/^([[:space:]]*export[[:space:]]+HIST(FILE)?SIZE[[:space:]]*=[[:space:]]*[0-9]+.*)$/# disabled by eternal-history setup: \1/' "$BASHRC"
    changed=1
    log "Commented out numeric history-size exports in ${BASHRC}:"
    grep -n '# disabled by eternal-history setup:' "$BASHRC" | sed 's/^/  /'
else
    log "No numeric HISTSIZE/HISTFILESIZE exports found in ${BASHRC} — nothing to disable."
fi

# --------------------------------------------------------------------------
# 3. Ensure the history file exists
# --------------------------------------------------------------------------
if [ ! -f "$HISTFILE_ETERNAL" ]; then
    touch "$HISTFILE_ETERNAL"
    log "Created ${HISTFILE_ETERNAL}"
else
    log "${HISTFILE_ETERNAL} already exists ($(wc -l < "$HISTFILE_ETERNAL") lines)."
fi

# --------------------------------------------------------------------------
# 4. Append-only protection
# --------------------------------------------------------------------------
if lsattr "$HISTFILE_ETERNAL" 2>/dev/null | awk '{print $1}' | grep -q 'a'; then
    log "${HISTFILE_ETERNAL} is already append-only (chattr +a)."
    exit 0
fi

log ""
log "Recommended: make ${HISTFILE_ETERNAL} append-only so no bash session"
log "can truncate or overwrite it:  chattr +a ${HISTFILE_ETERNAL}"
log "Note: only works on ext4-family filesystems (not btrfs, tmpfs, NFS)."
log ""

if yes_no "Apply chattr +a now?"; then
    sudo_cmd=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo_cmd="sudo"
        else
            warn "Not root and no sudo available — cannot set append-only flag."
            exit 1
        fi
    fi
    if $sudo_cmd chattr +a "$HISTFILE_ETERNAL"; then
        log "Done: ${HISTFILE_ETERNAL} is now append-only."
        log "To undo: sudo chattr -a ${HISTFILE_ETERNAL}"
    else
        warn "chattr +a failed — your filesystem may not support it (btrfs/tmpfs/NFS)."
        exit 1
    fi
else
    log "Skipped chattr +a. You can apply it later with:"
    log "  sudo chattr -a ${HISTFILE_ETERNAL}   # undo"
    log "  sudo chattr +a ${HISTFILE_ETERNAL}   # apply"
fi
