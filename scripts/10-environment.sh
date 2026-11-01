# General environment settings.

export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"

# History: bigger, deduplicated, with timestamps.
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT='%F %T '

# Never page anything smaller than a screen.
export LESS="-FRX"

# Make ls, grep, and friends colorful when supported.
if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    export LS_COLORS='di=01;34:ln=01;36:so=01;35:pi=33:ex=01;32'
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi
