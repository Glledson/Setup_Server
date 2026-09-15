#!/bin/bash
# lib/common.sh — Funções compartilhadas do Setup Server
# Autor: Glledson Olliver

# ─────────────────────────────────────────────────────────────
# Cores
# ─────────────────────────────────────────────────────────────

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
BOLD='\e[1m'
RESET='\e[0m'

# ─────────────────────────────────────────────────────────────
# Variáveis de caminho (definidas pelo orquestrador)
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="${LOG_FILE:-/var/log/upisp-setup.log}"
APT_LOG="${APT_LOG:-/tmp/upisp-apt.log}"
BACKUP_DIR="${BACKUP_DIR:-/root/setup_backup_$(date +%Y%m%d_%H%M%S)}"

# ─────────────────────────────────────────────────────────────
# Logging e output
# ─────────────────────────────────────────────────────────────

log() {
    echo "[$(date +'%d/%m/%Y %H:%M:%S')] $1" >> "$LOG_FILE"
}

exibir_resultado() {
    if [ "$1" -eq 0 ]; then
        printf "${GREEN}OK${RESET}\n"
    else
        printf "${RED}FAIL${RESET}\n"
    fi
}

info()  { printf "${CYAN}[INFO]${RESET}  %s\n" "$*"; log "[INFO] $*"; }
ok()    { printf "${GREEN}[OK]${RESET}    %s\n" "$*"; log "[OK] $*"; }
warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*"; log "[WARN] $*"; }
error() { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; log "[ERROR] $*"; }
head()  { printf "\n${BOLD}${CYAN}══ %s ══${RESET}\n" "$*"; }

step() {
    local desc="$1"; shift
    printf "  ${BLUE}→${RESET} %-55s" "$desc"
    local output rc=0
    output=$("$@" 2>&1) || rc=$?
    echo "$output" >> "$LOG_FILE" 2>/dev/null || true
    if [ $rc -eq 0 ]; then
        printf "${GREEN}OK${RESET}\n"
    else
        printf "${RED}FALHOU${RESET}\n"
        error "Comando falhou (rc=$rc): $*"
    fi
    return $rc
}

die() {
    error "$*"
    error "Log salvo em: $LOG_FILE"
    exit 1
}

# ─────────────────────────────────────────────────────────────
# Validações
# ─────────────────────────────────────────────────────────────

check_root() {
    if [ "$EUID" -ne 0 ]; then
        die "Execute este script como root."
    fi
}

checar_dependencias() {
    if ! command -v dialog > /dev/null 2>&1; then
        echo "Instalando dialog (necessário para o menu)..."
        apt-get update -y > /dev/null 2>&1
        apt-get install -y dialog > /dev/null 2>&1
        exibir_resultado $?
    fi
}

# ─────────────────────────────────────────────────────────────
# Backup
# ─────────────────────────────────────────────────────────────

init_backup() {
    mkdir -p "$BACKUP_DIR"
    info "Backups em: $BACKUP_DIR"
}

backup_file() {
    local file="$1"
    [ -f "$file" ] && cp -p "$file" "$BACKUP_DIR/$(basename "$file").bak" 2>/dev/null || true
}
