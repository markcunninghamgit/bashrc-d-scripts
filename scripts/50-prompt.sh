# Prompt setup. Loaded last so it can reflect everything before it.

# Only set PS1 if the user hasn't already (e.g. via a custom theme script).
if [ -z "${PS1_CUSTOM:-}" ]; then
    if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        PS1='\[\e[01;32m\]\u@\h\[\e[0m\]:\[\e[01;34m\]\w\[\e[0m\] \$ '
    else
        PS1='\u@\h:\w\$ '
    fi
fi

# Show current git branch in the prompt when available.
if command -v git >/dev/null 2>&1; then
    __git_prompt_branch() {
        local branch
        branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return 0
        printf ' (%s)' "$branch"
    }
    PS1="${PS1}"
    case "$PS1" in
        *'$(git '*|*'${'*) ;; # already dynamic
        *) PS1="${PS1%\\\$ *}\$(__git_prompt_branch)\\\$ " ;;
    esac
fi
