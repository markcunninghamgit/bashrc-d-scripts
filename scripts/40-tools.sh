# Optional tool integrations. Each is guarded so a missing tool is not an error.

# nvm (Node Version Manager)
if [ -s "${HOME}/.nvm/nvm.sh" ]; then
    . "${HOME}/.nvm/nvm.sh"
fi

# pyenv
if command -v pyenv >/dev/null 2>&1; then
    export PYENV_ROOT="${HOME}/.pyenv"
    [ -d "${PYENV_ROOT}/bin" ] && PATH="${PYENV_ROOT}/bin:${PATH}"
    eval "$(pyenv init -)"
fi

# direnv
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"

# fzf key bindings and completion
if command -v fzf >/dev/null 2>&1; then
    [ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && \
        . /usr/share/doc/fzf/examples/key-bindings.bash
    [ -f /usr/share/doc/fzf/examples/completion.bash ] && \
        . /usr/share/doc/fzf/examples/completion.bash
fi
