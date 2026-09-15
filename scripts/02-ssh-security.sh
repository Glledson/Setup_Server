#!/bin/bash
# scripts/02-ssh-security.sh — Configuração SSH e banners
# Autor: Glledson Olliver
# Chamado por setup_server.sh via source

configurar_ssh() {
    log "Configurando SSH (/etc/ssh/sshd_config)"

    set_sshd_option "Protocol" "2"
    set_sshd_option "DebianBanner" "no"
    set_sshd_option "PermitRootLogin" "prohibit-password"
    set_sshd_option "Port" "$SSH_PORT"

    local ssh_config="/etc/ssh/sshd_config"
    if grep -q "^Banner " "$ssh_config"; then
        sed -ri "s|^Banner .*|Banner /etc/issue.net|" "$ssh_config"
    else
        echo "Banner /etc/issue.net" >> "$ssh_config"
    fi

    if sshd -t; then
        systemctl restart ssh
        exibir_resultado $?
        log "SSH reconfigurado (porta $SSH_PORT)"
    else
        printf "${RED}Erro na configuração SSH. Não reiniciando serviço.\n${RESET}"
        log "ERRO: sshd -t falhou"
        exit 1
    fi
}

configurar_banner_pre_login() {
    log "Configurando banner pré-login (/etc/issue.net)"
    cp "$SCRIPT_DIR/config/issue.net" /etc/issue.net
}

configurar_banner_pos_login() {
    log "Configurando banner pós-login"
    cat > /etc/profile.d/upisp-banner.sh << 'EOF'
#!/bin/bash

HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
DATA=$(date +"%d/%m/%Y  %H:%M:%S")

cat << BANNER

╔══════════════════════════════════════════════╗
║        UP-ISP :: CONSULTORIA TÉCNICA       ║
╚══════════════════════════════════════════════╝

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

adicionar_chave_ssh_root() {
    log "Configurando chave SSH pública para root"
    local ssh_dir="/root/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    [ -f "$authorized_keys" ] || touch "$authorized_keys"

    if [ -n "${SSH_PUB_KEY:-}" ]; then
        if ! grep -Fq "$SSH_PUB_KEY" "$authorized_keys"; then
            echo "$SSH_PUB_KEY" >> "$authorized_keys"
            info "Chave SSH adicionada via variável SSH_PUB_KEY"
            log "Chave SSH adicionada via variável de ambiente"
        else
            info "Chave SSH já presente"
        fi
    else
        local key
        key=$(dialog --title "Chave SSH" \
            --inputbox "Cole a chave pública SSH (deixe vazio para pular):" 10 70 \
            3>&1 1>&2 2>&3) || true

        if [ -n "$key" ]; then
            if ! grep -Fq "$key" "$authorized_keys"; then
                echo "$key" >> "$authorized_keys"
                info "Chave SSH adicionada"
                log "Chave SSH adicionada via input"
            else
                info "Chave SSH já presente"
            fi
        else
            info "Adição de chave SSH pulada"
            log "Chave SSH pulada pelo usuário"
        fi
    fi

    chmod 600 "$authorized_keys"
}
