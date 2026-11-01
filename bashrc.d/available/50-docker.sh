# Docker helpers.

alias docker="sudo docker"

alias dkc='sudo docker compose'

dcr() {
    sudo docker compose down ${1:+"$1"}
    sudo docker compose up ${1:+"$1"}
}

dockerimagewhoami() {
    sudo docker run --rm -it --entrypoint /usr/bin/id "$1"
}

dockerimagebash() {
    sudo docker run --rm -it --entrypoint "${2:-/bin/sh}" "$1"
}

alias ollama="sudo docker exec -it ollama-docker-service ollama"

# Run node tooling in throwaway containers instead of installing it locally.
alias dnode='docker run -u $(id -u):$(id -g) -it --rm -v $(pwd):/app -w /app node:24-alpine node'
alias dnpm='docker run -u $(id -u):$(id -g) -it --rm -v $(pwd):/app -w /app node:24.14.0-alpine npm'
alias dnpx='docker run -u $(id -u):$(id -g) -it --rm -v $(pwd):/app -w /app node:24-alpine npx'
alias dastrorun='docker run -u $(id -u):$(id -g) -it -p 127.0.0.1:4321:4321 --rm -v $(pwd):/app -w /app node:24-alpine npm run devlistenall'

# pnpm equivalents.
alias dpnpm='docker run -u $(id -u):$(id -g) -it --rm -v $(pwd):/app -w /app ghcr.io/pnpm/pnpm pnpm'
alias dpnpx='docker run -u $(id -u):$(id -g) -it --rm -v $(pwd):/app -w /app ghcr.io/pnpm/pnpm pnpx'
