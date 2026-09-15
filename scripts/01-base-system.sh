#!/bin/bash
# scripts/01-base-system.sh — Preparação base do sistema
# Autor: Glledson Olliver
# Chamado por setup_server.sh via source

atualizar_sources_list() {
    log "Atualizando /etc/apt/sources.list"
    backup_file "/etc/apt/sources.list"
    cp "$SCRIPT_DIR/config/sources.list.trixie" /etc/apt/sources.list
    log "sources.list atualizado para Trixie"
}

atualizar_sistema() {
    log "Iniciando atualização do sistema"
    (
        echo 5
        echo "XXX"; echo "Atualizando lista de pacotes (apt update)..."; echo "XXX"
        apt-get update -y >> "$APT_LOG" 2>&1

        echo 40
        echo "XXX"; echo "Atualizando pacotes instalados (apt upgrade)..."; echo "XXX"
        apt-get upgrade -y >> "$APT_LOG" 2>&1

        echo 75
        echo "XXX"; echo "Atualizando distribuição (apt dist-upgrade)..."; echo "XXX"
        apt-get dist-upgrade -y >> "$APT_LOG" 2>&1

        echo 100
        echo "XXX"; echo "Concluído."; echo "XXX"
    ) | dialog --title "Atualizando sistema" --gauge "Iniciando..." 8 70 0
    log "Sistema atualizado"
}

instalar_pacotes() {
    log "Iniciando instalação de pacotes"
    local pacotes=(
        vim
        bash-completion
        fzf
        grc
        curl
        wget
        unzip
        man-db
        htop
        tree
        bmon
        hdparm
        mtr-tiny
        whois
        dnsutils
        net-tools
        ethtool
        rsync
        gnupg
        dnstop
        bind9-dnsutils
    )

    local total=${#pacotes[@]}
    local count=0

    (
        for pacote in "${pacotes[@]}"; do
            count=$((count + 1))
            local pct=$(( count * 100 / total ))
            echo "XXX"; echo "Instalando: $pacote ($count/$total)"; echo "XXX"
            echo "$pct"
            if ! dpkg -s "$pacote" > /dev/null 2>&1; then
                apt-get install -y "$pacote" >> "$APT_LOG" 2>&1
            fi
        done
    ) | dialog --title "Instalando pacotes essenciais" --gauge "Iniciando..." 8 70 0
    log "Pacotes instalados: ${pacotes[*]}"
}

configurar_bash_completion_global() {
    log "Configurando bash-completion global"
    local bashrc="/etc/bash.bashrc"
    if ! grep -q "bash-completion" "$bashrc"; then
        cat >> "$bashrc" <<'EOF'

# Autocompletar extra
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF
    fi
}

configurar_vim() {
    log "Configurando vim"
    sed -i 's/^"syntax on/syntax on/' /etc/vim/vimrc 2>/dev/null || true
    sed -i 's/^"set background=dark/set background=dark/' /etc/vim/vimrc 2>/dev/null || true
    cp "$SCRIPT_DIR/config/vimrc" /root/.vimrc
}

configurar_bashrc_root() {
    log "Configurando .bashrc do root"
    local root_bashrc="/root/.bashrc"
    local marcador="# UPISP_CUSTOM_ALIASES_START"

    if ! grep -q "$marcador" "$root_bashrc"; then
        cat >> "$root_bashrc" <<EOF

$marcador
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias ip='ip -c'
alias diff='diff --color=auto'
alias tail='grc tail'
alias ping='grc ping'
alias ps='grc ps'
alias ls='ls \$LS_OPTIONS'
alias ll='ls \$LS_OPTIONS -l'
alias l='ls \$LS_OPTIONS -lha'
export LS_OPTIONS='--color=auto'
eval "\$(dircolors)"
source /usr/share/doc/fzf/examples/key-bindings.bash
PS1='\\[\\033[1;32m\\]⏻ \\u\\[\\033[0;32m\\]@\\[\\033[1;34m\\]\\h\\[\\033[0;34m\\][\\[\\033[1;37m\\]\\w\\[\\033[0;34m\\]]\\[\\033[1;32m\\]\\$\\[\\033[0m\\]'
# UPISP_CUSTOM_ALIASES_END
EOF
    fi
}
