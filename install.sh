#!/bin/bash
# install.sh — Bootstrap: clona o repositório e executa o setup
# Uso: bash -c "$(curl -fsSL https://raw.githubusercontent.com/Glledson/Setup_Server/main/install.sh)"
set -euo pipefail

REPO_URL="https://github.com/Glledson/Setup_Server.git"
CLONE_DIR="/root/Setup_Server"

if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root."
    exit 1
fi

echo "Baixando Setup Server..."

if ! command -v git > /dev/null 2>&1; then
    apt-get update -y > /dev/null 2>&1
    apt-get install -y git > /dev/null 2>&1
fi

rm -rf "$CLONE_DIR"
git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"
chmod +x setup_server.sh
exec bash setup_server.sh "$@"
