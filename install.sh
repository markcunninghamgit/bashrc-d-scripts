#!/usr/bin/env bash
# Appends the ~/.bashrc.d sourcing block to ~/.bashrc (with backup).
# Safe to re-run: does nothing if the block is already present.

set -euo pipefail

BASHRC="${HOME}/.bashrc"
BASHRC_D="${HOME}/.bashrc.d"
BLOCK_MARKER="bashrc.d modular config"
SOURCING_BLOCK="# ${BLOCK_MARKER}
if [ -d \"\${HOME}/.bashrc.d\" ]; then
    for rc in \"\${HOME}\"/.bashrc.d/*.sh; do
        [ -f \"\$rc\" ] && . \"\$rc\"
    done
    unset rc
fi
"

if [ ! -d "$BASHRC_D" ]; then
    printf 'Error: %s does not exist. Clone this repo there first:\n' "$BASHRC_D" >&2
    printf '  git clone https://github.com/markcunninghamgit/bashrc-d-scripts.git %s\n' "$BASHRC_D" >&2
    exit 1
fi

if [ ! -f "$BASHRC" ]; then
    touch "$BASHRC"
elif grep -q "$BLOCK_MARKER" "$BASHRC" 2>/dev/null; then
    printf 'Sourcing block already present in %s — nothing to do.\n' "$BASHRC"
    exit 0
fi

cp "$BASHRC" "${BASHRC}.bak"
printf '%s\n' "$SOURCING_BLOCK" >> "$BASHRC"

printf 'Installed. Backup of your previous ~/.bashrc saved to %s.bak\n' "$BASHRC"
printf 'Restart your shell or run: exec bash\n'
