# Python virtual environment helpers.

# create a virtual environment (default: .venv)
venvcreate() {
    python3 -m venv "${1:-.venv}"
}

# activate a virtual environment (default: .venv)
venvactivate() {
    # shellcheck disable=SC1091
    . "${1:-.venv}/bin/activate"
}

# deactivate current virtual environment
alias venvdeactivate='deactivate'
