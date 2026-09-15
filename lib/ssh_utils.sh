#!/bin/bash
# lib/ssh_utils.sh — Funções auxiliares de configuração SSH
# Autor: Glledson Olliver

SSH_PORT="${SSH_PORT:-29019}"

set_sshd_option() {
    local ssh_config="/etc/ssh/sshd_config"
    local option="$1"
    local value="$2"
    if grep -qE "^\s*${option}\s+" "$ssh_config"; then
        sed -ri "s|^\s*${option}\s+.*|${option} ${value}|g" "$ssh_config"
    else
        echo "${option} ${value}" >> "$ssh_config"
    fi
}
