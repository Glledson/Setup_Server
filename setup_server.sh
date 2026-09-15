#!/bin/bash
# setup_server.sh — Orquestrador interativo do Setup Server
# Autor: Glledson Olliver https://www.linkedin.com/in/gledsom-oliveira/
# Descrição: Menu interativo (dialog) para provisionamento de servidores ISP

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carrega módulos
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ssh_utils.sh"
source "$SCRIPT_DIR/scripts/01-base-system.sh"
source "$SCRIPT_DIR/scripts/02-ssh-security.sh"

# Inicialização
check_root
: > "$APT_LOG"
touch "$LOG_FILE"

# ─────────────────────────────────────────────────────────────
# Execução de serviços modulares
# ─────────────────────────────────────────────────────────────

instalar_servico() {
    local script="$1"
    local label="$2"
    if [ ! -f "$script" ]; then
        warn "$label: script não encontrado — $script"
        return 1
    fi
    log "Iniciando serviço: $label"
    local rc=0
    bash "$script" || rc=$?
    if [ $rc -eq 0 ]; then
        exibir_resultado 0
        log "$label concluído"
    else
        exibir_resultado $rc
        warn "$label falhou (exit $rc)"
    fi
}

instalar_servicos() {
    log "Abrindo menu de configuração de serviços"
    local selecao
    selecao=$(dialog --title "UP-ISP :: Configuração de serviços" \
        --checklist "Selecione com ESPAÇO o que deseja executar e confirme com ENTER:" 20 78 6 \
        "MONITORAMENTO"  "Zabbix + Grafana"       OFF \
        "DNS RECURSIVO"  "Unbound + FRR (BGP)"   OFF \
        3>&1 1>&2 2>&3) || {
            log "Menu de serviços cancelado"
            return 0
        }

    [ -z "$selecao" ] && { log "Nenhum serviço selecionado"; return 0; }

    eval "local itens=($selecao)"

    for item in "${itens[@]}"; do
        case "$item" in
            "MONITORAMENTO") instalar_servico "$SCRIPT_DIR/scripts/services/monitoring.sh" "MONITORAMENTO" ;;
            "DNS RECURSIVO")  instalar_servico "$SCRIPT_DIR/scripts/services/dns-recursivo.sh" "DNS RECURSIVO" ;;
        esac
    done

    dialog --title "UP-ISP :: Serviços" \
        --msgbox "Serviços concluídos.\n\nLog completo: $LOG_FILE" 9 60
    log "Serviços finalizados"
}

# ─────────────────────────────────────────────────────────────
# Menu principal
# ─────────────────────────────────────────────────────────────

mostrar_menu() {
    dialog --title "UP-ISP :: Setup do servidor" \
        --checklist "Selecione com ESPAÇO e confirme com ENTER:" 22 78 12 \
        "SOURCES"    "Atualizar /etc/apt/sources.list (trixie)"       OFF \
        "UPDATE"     "Atualizar sistema (update/upgrade/dist-upgrade)" OFF \
        "SSH"        "Configurar SSH (porta $SSH_PORT)"               OFF \
        "PACOTES"    "Instalar pacotes essenciais"                    OFF \
        "BASHCOMP"   "Ativar bash-completion global"                  OFF \
        "VIM"        "Configurar vim (syntax, indentação)"            OFF \
        "BASHRC"     "Aliases e prompt no .bashrc do root"            OFF \
        "SSHKEY"     "Adicionar chave SSH pública ao root"            OFF \
        "BANNERPRE"  "Banner pré-login (/etc/issue.net)"              OFF \
        "BANNERPOS"  "Banner pós-login dinâmico"                      OFF \
        "SERVICOS"   "Instalar serviços (Zabbix, DNS, etc)"           OFF \
        "LIMPEZA"    "Remover temporários ao final"                   OFF \
        3>&1 1>&2 2>&3
}

executar_selecionados() {
    eval "local itens=($1)"

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
            LIMPEZA)   rm -f "$APT_LOG"; log "Temporários removidos" ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    checar_dependencias

    local selecao
    selecao=$(mostrar_menu) || { echo "Cancelado pelo usuário."; exit 0; }

    if [ -z "$selecao" ]; then
        dialog --title "UP-ISP :: Setup" --msgbox "Nenhuma opção selecionada. Encerrando." 8 60
        exit 0
    fi

    executar_selecionados "$selecao"

    dialog --title "UP-ISP :: Setup concluído" \
        --msgbox "✅ Tudo pronto!\n\nLog: $LOG_FILE" 10 60
}

main "$@"
