#!/bin/bash
# upisp-banner.sh — Configura banner institucional SSH, ambiente root e sistema
# Autor: Você
# Data: 2026-09-03
# Descrição: Menu interativo (dialog) para escolher o que executar,
#            com tela de progresso durante update/upgrade e instalação de pacotes.

set -euo pipefail

LOG_FILE="/var/log/upisp-setup.log"
APT_LOG="/tmp/upisp-apt.log"
: > "$APT_LOG"

# ─────────────────────────────────────────────────────────────
# Checagens iniciais
# ─────────────────────────────────────────────────────────────

if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute este script como root."
  exit 1
fi

exibir_resultado() {
    if [ "$1" -eq 0 ]; then
        printf "\e[32mOK\e[0m\n"
    else
        printf "\e[31mFAIL\e[0m\n"
    fi
}

log() {
    echo "[$(date +'%d/%m/%Y %H:%M:%S')] $1" >> "$LOG_FILE"
}

checar_dependencias() {
    # dialog é necessário para o menu e as telas de progresso.
    if ! command -v dialog > /dev/null 2>&1; then
        echo "Instalando dialog (necessário para o menu)..."
        apt-get update -y > /dev/null 2>&1
        apt-get install -y dialog > /dev/null 2>&1
        exibir_resultado $?
    fi
}

# ─────────────────────────────────────────────────────────────
# Funções de configuração (mesma lógica original, com pequenos ajustes)
# ─────────────────────────────────────────────────────────────

atualizar_sources_list() {
    log "Atualizando /etc/apt/sources.list"
    cp /etc/apt/sources.list /etc/apt/sources.list.bkp 2>/dev/null || true
    cat > /etc/apt/sources.list << EOF
deb https://ftp.debian.org/debian/ bookworm contrib main non-free non-free-firmware
# deb-src https://ftp.debian.org/debian/ bookworm contrib main non-free non-free-firmware

deb https://ftp.debian.org/debian/ bookworm-updates contrib main non-free non-free-firmware
# deb-src https://ftp.debian.org/debian/ bookworm-updates contrib main non-free non-free-firmware

deb https://ftp.debian.org/debian/ bookworm-proposed-updates contrib main non-free non-free-firmware
# deb-src https://ftp.debian.org/debian/ bookworm-proposed-updates contrib main non-free non-free-firmware

deb https://ftp.debian.org/debian/ bookworm-backports contrib main non-free non-free-firmware
# deb-src https://ftp.debian.org/debian/ bookworm-backports contrib main non-free non-free-firmware

deb https://security.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware
# deb-src https://security.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware
EOF
    log "sources.list atualizado"
}

# Atualiza o sistema mostrando uma barra de progresso (dialog --gauge)
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

configurar_ssh() {
    echo "Configurando SSH (/etc/ssh/sshd_config)..."
    log "Configurando SSH"

    local ssh_config="/etc/ssh/sshd_config"

    set_sshd_option() {
        local option="$1"
        local value="$2"
        if grep -qE "^\s*${option}\s+" "$ssh_config"; then
            sed -ri "s|^\s*${option}\s+.*|${option} ${value}|g" "$ssh_config"
        else
            echo "${option} ${value}" >> "$ssh_config"
        fi
    }

    set_sshd_option "Protocol" "2"
    set_sshd_option "DebianBanner" "no"
    set_sshd_option "PermitRootLogin" "prohibit-password"
    set_sshd_option "Port" "29019"

    if grep -q "^Banner " "$ssh_config"; then
        sed -ri "s|^Banner .*|Banner /etc/issue.net|" "$ssh_config"
    else
        echo "Banner /etc/issue.net" >> "$ssh_config"
    fi

    if sshd -t; then
        systemctl restart ssh
        exibir_resultado $?
        log "SSH reconfigurado e reiniciado (porta 29019)"
    else
        echo -e "\e[31mErro na configuração SSH. Não foi possível reiniciar o serviço.\e[0m"
        log "ERRO: sshd -t falhou, SSH não foi reiniciado"
        exit 1
    fi
}

# Instala os pacotes mostrando progresso pacote a pacote
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
        echo -e "\n# Autocompletar extra" >> "$bashrc"
        echo "if ! shopt -oq posix; then" >> "$bashrc"
        echo "  if [ -f /usr/share/bash-completion/bash_completion ]; then" >> "$bashrc"
        echo "    . /usr/share/bash-completion/bash_completion" >> "$bashrc"
        echo "  elif [ -f /etc/bash_completion ]; then" >> "$bashrc"
        echo "    . /etc/bash_completion" >> "$bashrc"
        echo "  fi" >> "$bashrc"
        echo "fi" >> "$bashrc"
    fi
}

configurar_vim() {
    log "Configurando vim"
    sed -i 's/^"syntax on/syntax on/' /etc/vim/vimrc 2>/dev/null || true
    sed -i 's/^"set background=dark/set background=dark/' /etc/vim/vimrc 2>/dev/null || true

    cat > /root/.vimrc <<EOF
set showmatch
set ts=4
set sts=4
set sw=4
set autoindent
set smartindent
set smarttab
set expandtab
"set number
EOF
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

adicionar_chave_ssh_root() {
    log "Adicionando chave SSH pública ao root"
    local ssh_dir="/root/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"
    local ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5YQXUBfRipUlXLtPEt0bYMzBmTHkkRtgZUi0j/3M/TJQ8h1DimeeQxi7/zx7edEwNL4YPPE6UaSnCnHEMzFU0stoKf7uklw8tD+l5jdQmbbElGfDntOturXUh34U+rEn3EEgBThaIvWAU+5ALnMXYQ98nx2tld8Dm2n2zmW7+3d6OXQPtG5XI54ZqTvRA7GPyW8O1U89uX6HAE3o1Qj2VNrVW/klTgDxL8H0Pnh1UIWCQMqsGCBmU/jv6DAKwhHBCrDknOTI90bx/n8LpMlJcvj812Xb337v7HiSNvh2IHsyYlHmD/rrnNj7/BPBXVQfLJCaEr6FAaWKiyjdpqvZR7E2mIIAmOK8gUSsZlMkZnDLTHa3dFhomXolbPEurC94PnmSOxsbqGb6sxwvCuzx44YSn6c5gjta+h5nx5rDlzmYbBaGlTryDun8maLzZsTCqm2mPAZipPBLX+OC4cPDWtVmwoWrZYDZ/OsDnrxthhFi2a6pxG5AUaKAM5E0aKGfP0d4VJFfO9u9Ps0WjdsKeVUpC0R2WjxWfXp8DmRltLnZSOoTf6uXEPHLP9s4Jmw9ETRbaqPgg+GmYPYUQBkO5KfYvmEzL1AoEc7/dMAWHCC9f9Qqa4E/9o7VwAXQrUpvFgflZ7J8SKnYxRVokxLPxIupdHn6VXzRdB7ZpmDJQew== root@upsip-automacoes"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    if [ ! -f "$authorized_keys" ] || ! grep -Fq "$ssh_key" "$authorized_keys"; then
        echo "$ssh_key" >> "$authorized_keys"
    fi
    chmod 600 "$authorized_keys"
}

configurar_banner_pre_login() {
    log "Configurando banner pré-login (/etc/issue.net)"
    cat > /etc/issue.net << EOF
Acesso restrito. Apenas usuários autorizados.
Uso indevido pode causar sanções técnicas
e/ou administrativas.

cc: noc@upisp.com.br
EOF
}

configurar_banner_pos_login() {
    log "Configurando banner pós-login (/etc/profile.d/upisp-banner.sh)"
    cat > /etc/profile.d/upisp-banner.sh << 'EOF'
#!/bin/bash

HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
DATA=$(date +"%d/%m/%Y  %H:%M:%S")

cat << BANNER

╔════════════════════════════════════════════╗
║        UP-ISP :: CONSULTORIA TÉCNICA       ║
╚════════════════════════════════════════════╝

Hostname..: $HOSTNAME
IP Local..: $IP
Data/Hora.: $DATA

Acesso restrito. Apenas usuários autorizados.
Atividades são monitoradas e registradas.
Uso indevido pode causar sanções técnicas
e/ou administrativas.

BANNER
EOF
    chmod +x /etc/profile.d/upisp-banner.sh
}

excluir_prepara() {
    if [ -f "./prepara.sh" ]; then
        rm -f "./prepara.sh"
        log "prepara.sh removido"
    fi
}

# ─────────────────────────────────────────────────────────────
# Funções de serviços individuais (chamadas por instalar_servicos)
# ─────────────────────────────────────────────────────────────

servico_monitoramento() {
    log "Configurando MONITORAMENTO (Zabbix Agent 2)"
}

servico_smokeping() {
    log "Instalando SMOKINGPING (SmokePing)"
}

servico_dns_recursivo() {
    log "Configurando DNS RECURSIVO (Unbound)"
}

servico_dns_reverso() {
    log "Configurando DNS REVERSO (BIND9)"
}

servico_ftp() {
    log "Instalando e configurando FTP (vsftpd)"
}

servico_ntp() {
    log "Configurando NTP (chrony) com pool NTP.br"
}

servico_speedtest() {
    log "Instalando SPEEDTEST CLI (Ookla)"
}

servico_minha_conexao() {
    log "Configurando monitoramento da própria conexão (vnstat + mtr)"
}

servico_nperf() {
    log "Instalando iperf3 (substituto de nPerf para testes de throughput)"
}

servico_graylog() {
    log "Instalando GRAYLOG (Docker: MongoDB + OpenSearch + Graylog)"
}

servico_phpipam() {
    log "Instalando PHPIPAM (Docker)"
}

servico_krill() {
    log "Instalando KRILL (RPKI Certificate Authority)"
}

# ─────────────────────────────────────────────────────────────
# Menu de serviços (checklist) + execução dos itens marcados
# ─────────────────────────────────────────────────────────────

instalar_servicos() {
    log "Abrindo menu de configuração de serviços"
    local selecao
    selecao=$(dialog --title "UP-ISP :: Configuração de serviços" \
        --checklist "Selecione com ESPAÇO o que deseja executar e confirme com ENTER:" 22 78 12 \
        "MONITORAMENTO"  "Instalar e configurar ferramentas de monitoramento"     OFF \
        "SMOKINGPING"    "Instalar e configurar SmokingPing"                     OFF \
        "DNS RECURSIVO"  "Configurar DNS recursivo"                              OFF \
        "DNS REVERSO"    "Configurar DNS reverso"                                OFF \
        "FTP"            "Configurar FTP"                                       OFF \
        "NTP"            "Configurar NTP"                                       OFF \
        "SPEEDTEST"      "Configurar Speedtest"                                 OFF \
        "MINHA CONEXÃO"  "Configurar minha conexão"                             OFF \
        "NPERF"          "Configurar Nperf"                                     OFF \
        "GRAYLOG"        "Configurar Graylog"                                   OFF \
        "PHPIPAM"        "Configurar PHPIPAM"                                   OFF \
        "KRILL"          "Configurar Krill"                                     OFF \
        3>&1 1>&2 2>&3) || {
            log "Menu de serviços cancelado pelo usuário"
            return 0
        }

    if [ -z "$selecao" ]; then
        dialog --title "UP-ISP :: Serviços" --msgbox "Nenhum serviço selecionado." 8 60
        log "Nenhum serviço selecionado no submenu"
        return 0
    fi

    eval "local itens=($selecao)"

    for item in "${itens[@]}"; do
        case "$item" in
            "MONITORAMENTO") servico_monitoramento ;;
            "SMOKINGPING")   servico_smokeping ;;
            "DNS RECURSIVO") servico_dns_recursivo ;;
            "DNS REVERSO")   servico_dns_reverso ;;
            "FTP")           servico_ftp ;;
            "NTP")           servico_ntp ;;
            "SPEEDTEST")     servico_speedtest ;;
            "MINHA CONEXÃO") servico_minha_conexao ;;
            "NPERF")         servico_nperf ;;
            "GRAYLOG")       servico_graylog ;;
            "PHPIPAM")       servico_phpipam ;;
            "KRILL")         servico_krill ;;
        esac
    done

    dialog --title "UP-ISP :: Serviços" --msgbox "Serviços selecionados foram configurados.\n\nLog completo em: $LOG_FILE" 9 60
    log "Configuração de serviços concluída: ${itens[*]}"
}

# ─────────────────────────────────────────────────────────────
# Menu de seleção (dialog --checklist)
# ─────────────────────────────────────────────────────────────

mostrar_menu() {
    dialog --title "UP-ISP :: Setup do servidor" \
        --checklist "Selecione com ESPAÇO o que deseja executar e confirme com ENTER:" 22 78 12 \
        "SOURCES"    "Atualizar /etc/apt/sources.list (bookworm)"           OFF \
        "UPDATE"     "Atualizar sistema (update/upgrade/dist-upgrade)"      OFF \
        "SSH"        "Configurar SSH (porta 29019, banner, root sem senha)" OFF \
        "PACOTES"    "Instalar pacotes essenciais (vim, htop, mtr, etc)"    OFF \
        "BASHCOMP"   "Ativar bash-completion global"                        OFF \
        "VIM"        "Configurar vim (syntax, indentação)"                  OFF \
        "BASHRC"     "Configurar aliases e prompt no .bashrc do root"       OFF \
        "SSHKEY"     "Adicionar chave SSH pública ao root"                  OFF \
        "BANNERPRE"  "Configurar banner pré-login (/etc/issue.net)"         OFF \
        "BANNERPOS"  "Configurar banner pós-login dinâmico"                 OFF \
        "SERVICOS"   "Configurar serviços do sistema"                       OFF \
        "LIMPEZA"    "Remover prepara.sh ao final (auto-limpeza)"           OFF \
        3>&1 1>&2 2>&3
}


executar_selecionados() {
    local selecao="$1"

    # Remove aspas que o dialog coloca em volta de cada item
    eval "local itens=($selecao)"

    for item in "${itens[@]}"; do
        case "$item" in
            SOURCES)   atualizar_sources_list ;;
            UPDATE)    atualizar_sistema ;;
            SSH)       configurar_ssh ;;
            PACOTES)   instalar_pacotes ;;
            BASHCOMP)  configurar_bash_completion_global ;;
            VIM)       configurar_vim ;;
            BASHRC)    configurar_bashrc_root ;;
            SSHKEY)    adicionar_chave_ssh_root ;;
            BANNERPRE) configurar_banner_pre_login ;;
            BANNERPOS) configurar_banner_pos_login ;;
            SERVICOS)  instalar_servicos ;;
            LIMPEZA)   excluir_prepara ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    touch "$LOG_FILE"
    checar_dependencias

    local selecao
    selecao=$(mostrar_menu) || { echo "Cancelado pelo usuário."; exit 0; }

    if [ -z "$selecao" ]; then
        dialog --title "UP-ISP :: Setup" --msgbox "Nenhuma opção selecionada. Encerrando." 8 60
        exit 0
    fi

    executar_selecionados "$selecao"

    dialog --title "UP-ISP :: Setup concluído" \
        --msgbox "✅ Tudo pronto!\n\nAs opções selecionadas foram aplicadas.\nLog completo em: $LOG_FILE" 10 60
}

main "$@"