# Small helper functions.

# mkdir + cd in one step.
mkcd() {
    mkdir -p -- "$1" && cd -- "$1"
}

# Extract any archive by extension.
extract() {
    [ -f "$1" ] || { printf 'extract: %s not found\n' "$1" >&2; return 1; }
    case "$1" in
        *.tar.bz2|*.tbz2) tar xjf "$1" ;;
        *.tar.gz|*.tgz)   tar xzf "$1" ;;
        *.tar.xz)         tar xJf "$1" ;;
        *.tar)            tar xf  "$1" ;;
        *.bz2)            bunzip2 "$1" ;;
        *.gz)             gunzip "$1" ;;
        *.zip)            unzip "$1" ;;
        *.7z)             7z x "$1" ;;
        *)                printf 'extract: unknown archive type: %s\n' "$1" >&2; return 1 ;;
    esac
}

# Show the top processes by CPU and memory.
psmem() { ps aux | sort -rnk 6 | head "${1:-10}"; }
pscpu() { ps aux | sort -rnk 3 | head "${1:-10}"; }
