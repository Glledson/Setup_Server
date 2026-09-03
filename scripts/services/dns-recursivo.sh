#!/bin/bash
# =============================================================================
# Script de Provisionamento: DNS Recursivo (Unbound) + BGP (FRR)
# Compatível com: Debian 13 "Trixie" (kernel 6.12 LTS, systemd 257, FRR 10.3)
# Versão: 3.0
# =============================================================================
# USO: bash setup_trixie.sh [--no-reboot] [--skip-bgp] [--asn XXXXX]
# =============================================================================

# --- NÃO usar set -e globalmente: o step() faz controle de erro próprio ---
# --- Usamos set -uo pipefail para detectar variáveis não definidas e pipes ---
set -uo pipefail

# =============================================================================
# CONSTANTES E CONFIGURAÇÕES GLOBAIS
# =============================================================================

readonly RUN_TS=$(date +%Y%m%d_%H%M%S)           # timestamp único para toda a execução
readonly VERSION="3.1-$(date +%Y%m%d)"           # versão com data de build
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/var/log/setup_trixie_${RUN_TS}.log"
readonly SCRIPT_BLOCKLIST="/usr/local/bin/bloqueio_unbound.sh"
readonly TIMER_UNIT="unbound-blocklist.timer"
readonly BACKUP_DIR="/root/setup_backup_${RUN_TS}" # mesmo timestamp do log

# IPs fixos dos loopbacks DNS (altere se necessário)
readonly DNS_LO_IPV4_1="10.10.10.10"
readonly DNS_LO_IPV4_2="10.10.11.11"
readonly DNS_LO_IPV6_1="fc00::10:10:10:10"
readonly DNS_LO_IPV6_2="fc00::10:10:11:11"

# Flags de controle (podem ser sobrescritas por argumentos CLI)
OPT_REBOOT=true
OPT_ASN=""

# =============================================================================
# CORES E FUNÇÕES DE OUTPUT
# =============================================================================

RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; CYAN='\e[36m'
BLUE='\e[34m'; BOLD='\e[1m'; RESET='\e[0m'

_log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    # Saída no terminal (com cor)
    case "$level" in
        INFO)  printf "${CYAN}[INFO]${RESET}  %s\n" "$msg" ;;
        OK)    printf "${GREEN}[OK]${RESET}    %s\n" "$msg" ;;
        WARN)  printf "${YELLOW}[WARN]${RESET}  %s\n" "$msg" ;;
        ERROR) printf "${RED}[ERROR]${RESET} %s\n" "$msg" >&2 ;;
        STEP)  printf "  ${BLUE}→${RESET} %-55s" "$msg" ;;
        PASS)  printf "${GREEN}OK${RESET}\n" ;;
        FAIL)  printf "${RED}FALHOU${RESET}\n" ;;
        SKIP)  printf "${YELLOW}JÁ FEITO${RESET}\n" ;;
        HEAD)  printf "\n${BOLD}${CYAN}══ %s ══${RESET}\n" "$msg" ;;
    esac
    # Saída no log (sem cor, com timestamp)
    echo "[$ts] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

info()  { _log INFO  "$*"; }
ok()    { _log OK    "$*"; }
warn()  { _log WARN  "$*"; }
error() { _log ERROR "$*"; }
head()  { _log HEAD  "$*"; }

# Executa um comando com output controlado.
# Retorna o código de saída real do comando (não mata o script).
step() {
    local desc="$1"; shift
    _log STEP "$desc"
    local output
    local rc=0
    # Captura stdout+stderr para o log, exibe apenas resultado
    output=$("$@" 2>&1) || rc=$?
    echo "$output" >> "$LOG_FILE" 2>/dev/null || true
    if [ $rc -eq 0 ]; then
        _log PASS
    else
        _log FAIL
        error "Comando falhou (rc=$rc): $*"
        error "Saída: $output"
    fi
    return $rc
}

# Igual ao step() mas não para se falhar (usado para passos opcionais)
step_soft() {
    local desc="$1"; shift
    _log STEP "$desc"
    local output
    local rc=0
    output=$("$@" 2>&1) || rc=$?
    echo "$output" >> "$LOG_FILE" 2>/dev/null || true
    if [ $rc -eq 0 ]; then _log PASS; else _log WARN; fi
    return $rc
}

die() {
    error "$*"
    error "Log salvo em: $LOG_FILE"
    exit 1
}

# =============================================================================
# PARSING DE ARGUMENTOS CLI
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-reboot)  OPT_REBOOT=false ;;
            --skip-bgp)   OPT_ASN="00000" ;;   # alias de --asn 00000
            --asn)        shift; OPT_ASN="${1:-}" ;;
            --help|-h)
                echo "Uso: $SCRIPT_NAME [--no-reboot] [--skip-bgp] [--asn XXXXX]"
                echo "  --no-reboot   Não reinicia ao final"
                echo "  --skip-bgp    Pula configuração BGP (equivalente a --asn 00000)"
                echo "  --asn XXXXX   Define ASN sem prompt interativo (00000 = sem BGP)"
                exit 0
                ;;
            *) warn "Argumento desconhecido: $1" ;;
        esac
        shift
    done
}

# =============================================================================
# VALIDAÇÕES INICIAIS
# =============================================================================

check_root() {
    [[ $EUID -eq 0 ]] || die "Este script deve ser executado como root."
}

check_debian_trixie() {
    if [[ -f /etc/os-release ]]; then
        # NÃO usar 'source /etc/os-release' — colide com readonly VERSION do script
        local codename pretty
        codename=$(grep  -Po '(?<=^VERSION_CODENAME=).+' /etc/os-release | tr -d '"' || true)
        pretty=$(grep    -Po '(?<=^PRETTY_NAME=).+'     /etc/os-release | tr -d '"' || true)
        if [[ "${codename:-}" != "trixie" ]]; then
            warn "Sistema detectado: ${pretty:-desconhecido}"
            warn "Este script foi otimizado para Debian 13 Trixie."
        fi
    fi
}

# Garante que backup_dir existe antes de qualquer modificação
init_backup() {
    mkdir -p "$BACKUP_DIR"
    info "Backups de arquivos originais em: $BACKUP_DIR"
}

backup_file() {
    local file="$1"
    [[ -f "$file" ]] && cp -p "$file" "$BACKUP_DIR/$(basename "$file").bak" 2>/dev/null || true
}

# =============================================================================
# SEÇÃO 1 — COLETA DE INFORMAÇÕES DE REDE
# =============================================================================

collect_network_info() {
    head "DETECÇÃO DE REDE"

    # --- Interface primária ---
    # Evita pipeline com set -uo pipefail: separa em duas etapas sem subshell aninhado
    local route_output
    route_output=$(ip route show 2>/dev/null) || true

    PRIMARY_IF=""
    # Tenta rota 'default' primeiro
    PRIMARY_IF=$(echo "$route_output" | awk '/^default/ {print $5; exit}')
    # Fallback: primeira interface não-loopback que tiver IP
    if [[ -z "$PRIMARY_IF" ]]; then
        PRIMARY_IF=$(ip -4 addr show 2>/dev/null \
            | awk '/^[0-9]+:/ && !/loopback/ {gsub(":",""); print $2; exit}')
    fi
    if [[ -z "$PRIMARY_IF" ]]; then
        error "Interfaces disponíveis:"
        ip link show 2>/dev/null | awk '/^[0-9]+:/ {print "  "$0}' >&2 || true
        die "Não foi possível detectar a interface de rede primária."
    fi

    # --- IPs e Gateways ---
    ipv4_address=$(ip -4 addr show "$PRIMARY_IF" | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    ipv4_gateway=$(ip route show default dev "$PRIMARY_IF" | awk '/default/ {print $3; exit}')
    ipv6_address=$(ip -6 addr show "$PRIMARY_IF" scope global | awk '/inet6/ {split($2,a,"/"); print a[1]; exit}')
    ipv6_gateway=$(ip -6 route show default dev "$PRIMARY_IF" | awk '/default/ {print $3; exit}')

    [[ -n "$ipv4_address" ]] || die "Não foi possível detectar o endereço IPv4 em $PRIMARY_IF."
    [[ -n "$ipv4_gateway" ]] || die "Não foi possível detectar o gateway IPv4."


    IPV6_PREFIX=""
    HAS_IPV6=false
    if [[ -n "$ipv6_address" && -n "$ipv6_gateway" ]]; then
        HAS_IPV6=true
        # Calcula prefixo /64 para o access-control do Unbound
        if command -v python3 &>/dev/null; then
            IPV6_PREFIX=$(python3 -c "
import ipaddress, sys
try:
    net = ipaddress.IPv6Network('${ipv6_address}/64', strict=False)
    print(str(net))
except Exception as e:
    sys.exit(1)
" 2>/dev/null) || IPV6_PREFIX=""
        fi
        if [[ -z "$IPV6_PREFIX" ]]; then
            # Fallback manual: pega os 4 primeiros grupos e completa com ::/64
            IPV6_PREFIX=$(echo "$ipv6_address" \
                | awk -F: '{printf "%s:%s:%s:%s::/64\n",$1,$2,$3,$4}')
        fi
    else
        warn "IPv6 não detectado — configurações IPv6 serão omitidas."
    fi

    # --- CPU tuning ---
    CPU_CORES=$(nproc 2>/dev/null || echo 1)
    UNBOUND_THREADS=$(( CPU_CORES > 8 ? 8 : CPU_CORES ))

    # Slabs: próxima potência de 2 acima de UNBOUND_THREADS, máx 8
    local s=1
    while (( s < UNBOUND_THREADS )); do s=$(( s * 2 )); done
    UNBOUND_SLABS=$(( s > 8 ? 8 : s ))

    # --- Resumo ---
    info "Interface : $PRIMARY_IF"
    info "IPv4      : $ipv4_address  |  GW: $ipv4_gateway"
    if $HAS_IPV6; then
        info "IPv6      : $ipv6_address  |  GW: $ipv6_gateway  |  Prefixo: $IPV6_PREFIX"
    fi
    info "CPUs      : $CPU_CORES  |  Threads Unbound: $UNBOUND_THREADS  |  Slabs: $UNBOUND_SLABS"
}

# =============================================================================
# SEÇÃO 2 — COLETA DO ASN
# =============================================================================

collect_asn() {
    head "CONFIGURAÇÃO DO ASN"

    # Se passado via CLI (incluindo --skip-bgp que seta 00000), valida e usa
    if [[ -n "$OPT_ASN" ]]; then
        [[ "$OPT_ASN" =~ ^[0-9]+$ ]] || die "ASN inválido via --asn: '$OPT_ASN'"
        ASN="$OPT_ASN"
        [[ "$ASN" == "00000" ]] \
            && info "BGP desativado (ASN=00000)" \
            || info "ASN definido via argumento: $ASN"
        return
    fi

    # Modo interativo
    while true; do
        ASN=$(whiptail --title "Configuração BGP — ASN" \
            --inputbox \
            "Insira o ASN do servidor.\n\nUse '00000' para pular a configuração BGP." \
            10 60 3>&1 1>&2 2>&3) || die "Instalação cancelada pelo usuário."

        [[ -z "$ASN" ]] && {
            whiptail --title "Aviso" --msgbox "Campo vazio. Tente novamente." 8 45
            continue
        }

        [[ "$ASN" =~ ^[0-9]+$ ]] || {
            whiptail --title "Erro" --msgbox "Valor '$ASN' não é numérico." 8 45
            continue
        }

        whiptail --title "Confirmar ASN" \
            --yesno "ASN informado: $ASN\n\nConfirmar?" 10 50 && break
    done

    info "ASN: $ASN"
}

# =============================================================================
# SEÇÃO 3 — DEPENDÊNCIAS MÍNIMAS
# =============================================================================

install_bootstrap() {
    head "DEPENDÊNCIAS INICIAIS"
    step "Instalando whiptail, curl, wget, lsb-release..." \
        apt-get install -y whiptail curl wget lsb-release ca-certificates gnupg > /dev/null 2>&1
}

# =============================================================================
# SEÇÃO 4 — INTERFACES DE LOOPBACK
# =============================================================================

configure_loopbacks() {
    head "INTERFACES DE LOOPBACK"

    backup_file "/etc/network/interfaces.d/loopback.conf"

    # Aliases distintos (lo:0 e lo:1) — CORRIGIDO em relação ao original
    cat > /etc/network/interfaces.d/loopback.conf << EOF
# Loopback aliases para serviço DNS — gerado por setup_trixie.sh v${VERSION}
auto lo:0
iface lo:0 inet static
    address ${DNS_LO_IPV4_1}/32

auto lo:1
iface lo:1 inet static
    address ${DNS_LO_IPV4_2}/32
EOF

    if $HAS_IPV6; then
        cat >> /etc/network/interfaces.d/loopback.conf << EOF

# IPv6 loopbacks
iface lo inet6 static
    address ${DNS_LO_IPV6_1}/128

iface lo inet6 static
    address ${DNS_LO_IPV6_2}/128
EOF
    fi

    # Aplica sem depender de reboot
    step_soft "Subindo lo:0..." ifup lo:0 2>/dev/null
    step_soft "Subindo lo:1..." ifup lo:1 2>/dev/null

    # Verifica se os IPs responderam
    for ip in "$DNS_LO_IPV4_1" "$DNS_LO_IPV4_2"; do
        if ip addr show lo | grep -q "$ip"; then
            ok "Loopback $ip ativo"
        else
            warn "Loopback $ip não detectado — será ativado no próximo boot"
        fi
    done
}

# =============================================================================
# SEÇÃO 5 — REPOSITÓRIOS
# =============================================================================

configure_repos() {
    head "REPOSITÓRIOS APT — DEBIAN 13 TRIXIE"

    backup_file "/etc/apt/sources.list"

    # Obtém codename dinamicamente (fallback para 'trixie')
    local codename
    codename=$(lsb_release -sc 2>/dev/null || echo "trixie")

    # Repositório FRR upstream (para versão mais recente que a do Trixie)
    step "Importando chave GPG do FRRouting..." \
        bash -c "curl -fsSL https://deb.frrouting.org/frr/keys.gpg \
            | tee /usr/share/keyrings/frrouting.gpg > /dev/null"

    step "Adicionando repositório FRR (${codename} frr-stable)..." \
        bash -c "echo 'deb [signed-by=/usr/share/keyrings/frrouting.gpg] \
https://deb.frrouting.org/frr ${codename} frr-stable' \
            > /etc/apt/sources.list.d/frr.list"
}

# =============================================================================
# SEÇÃO 6 — SYSCTL / KERNEL
# =============================================================================

configure_kernel() {
    head "PARÂMETROS DE KERNEL (SYSCTL)"

    # Usa /etc/sysctl.d/ — não polui o sysctl.conf principal
    cat > /etc/sysctl.d/99-isp-tuning.conf << 'SYSCTL'
# ISP Tuning — setup_trixie.sh
# Memória / Swap
vm.swappiness=10
vm.vfs_cache_pressure=50

# Buffers TCP/UDP (2 GB)
net.core.rmem_max=2147483647
net.core.wmem_max=2147483647
net.ipv4.tcp_rmem=4096 87380 2147483647
net.ipv4.tcp_wmem=4096 65536 2147483647

# Conntrack (ISP: 10 M conexões)
net.netfilter.nf_conntrack_buckets=512000
net.netfilter.nf_conntrack_max=10000000

# Roteamento
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1

# Kernel 6.12 LTS: BBR3 + FQ (descomente para habilitar)
# net.ipv4.tcp_congestion_control=bbr
# net.core.default_qdisc=fq

# Proteção contra ataques de roteamento
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
SYSCTL

    # Evita duplicata no modules-load.d
    local mod_conf="/etc/modules-load.d/conntrack.conf"
    if ! grep -q "^nf_conntrack$" "$mod_conf" 2>/dev/null; then
        echo "nf_conntrack" >> "$mod_conf"
    fi

    step "Carregando nf_conntrack..." modprobe nf_conntrack
    step "Aplicando sysctl (sysctl --system)..." bash -c "sysctl --system > /dev/null 2>&1"
}

# =============================================================================
# SEÇÃO 7 — GRUB / APPARMOR
# =============================================================================

configure_grub() {
    head "GRUB — DESATIVAR APPARMOR"

    mkdir -p /etc/default/grub.d

    # Usa variável para não conflitar com outros arquivos em grub.d
    cat > /etc/default/grub.d/99-apparmor-off.cfg << 'GRUB'
# Desativa AppArmor — setup_trixie.sh
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=0"
GRUB

    step "Atualizando GRUB..." bash -c "update-grub > /dev/null 2>&1"
}

# =============================================================================
# SEÇÃO 8 — ATUALIZAÇÃO DO SISTEMA
# =============================================================================

update_system() {
    head "ATUALIZAÇÃO DO SISTEMA"

    step "apt-get update..."       bash -c "apt-get update -y > /dev/null 2>&1"
    step "apt-get upgrade..."      bash -c "apt-get upgrade -y > /dev/null 2>&1"
    step "apt-get dist-upgrade..."  bash -c "apt-get dist-upgrade -y > /dev/null 2>&1"
    step "apt-get autoremove..."   bash -c "apt-get autoremove -y > /dev/null 2>&1"
}

# =============================================================================
# SEÇÃO 9 — INSTALAÇÃO DE PACOTES
# =============================================================================

install_packages() {
    head "INSTALAÇÃO DE PACOTES"

    local pacotes=(
        unbound
        irqbalance
        ntpsec
        frr
        frr-doc
        frr-pythontools
        frr-rpki-rtrlib
        python3          # Necessário para cálculo de slabs e prefixo IPv6
    )

    for pacote in "${pacotes[@]}"; do
        _log STEP "Pacote: $pacote"
        if dpkg -s "$pacote" > /dev/null 2>&1; then
            _log SKIP
        else
            apt-get install -y "$pacote" >> "$LOG_FILE" 2>&1 && _log PASS || _log WARN
        fi
    done

    step "Habilitando irqbalance..." systemctl enable irqbalance > /dev/null 2>&1
}

# =============================================================================
# SEÇÃO 11 — UNBOUND
# =============================================================================

configure_unbound() {
    head "UNBOUND — CONFIGURAÇÃO"

    # Diretórios e log
    mkdir -p /var/log/unbound /var/lib/unbound
    touch /var/log/unbound/unbound.log
    chown -R unbound:unbound /var/log/unbound/ /var/lib/unbound/
    step "Permissões de log OK..." true

    # Root hints via HTTPS (mais seguro que FTP)
    step "Baixando root hints (HTTPS)..." \
        wget -q -O /etc/unbound/named.cache \
            https://www.internic.net/domain/named.cache

    # Logrotate com reload gracioso (não restart)
    cat > /etc/logrotate.d/unbound << 'LOGROTATE'
/var/log/unbound/unbound.log {
    weekly
    missingok
    rotate 4
    compress
    notifempty
    create 640 unbound unbound
    postrotate
        systemctl kill -s HUP unbound.service 2>/dev/null || true
    endscript
}
LOGROTATE

    # Monta blocos condicionais de IPv6
    local iface_ipv6="" outgoing_ipv6="" acl_ipv6="" do_ip6="no"
    if $HAS_IPV6; then
        do_ip6="yes"
        iface_ipv6="
	interface: ::1
	interface: ${DNS_LO_IPV6_1}
	interface: ${DNS_LO_IPV6_2}"
        outgoing_ipv6="
	outgoing-interface: ${ipv6_address}"
        acl_ipv6="
	# IPv6 loopbacks DNS
	access-control: ::1/128 allow
	access-control: ${DNS_LO_IPV6_1}/128 allow
	access-control: ${DNS_LO_IPV6_2}/128 allow
	# Prefixo do AS (/64)
	access-control: ${IPV6_PREFIX} allow
	# Bloqueio padrão IPv6
	access-control: ::/0 refuse"
    fi

    # Gera configuração principal com variáveis expandidas
    cat > /etc/unbound/unbound.conf.d/upisp.conf << EOF
# Unbound — gerado por setup_trixie.sh v${VERSION}
server:

	# ── Interfaces de escuta ──────────────────────────────────────────
	interface: 127.0.0.1
	interface: ${DNS_LO_IPV4_1}
	interface: ${DNS_LO_IPV4_2}${iface_ipv6}

	interface-automatic: no

	# ── Interfaces de saída ──────────────────────────────────────────
	outgoing-interface: ${ipv4_address}${outgoing_ipv6}

	# ── Protocolos ───────────────────────────────────────────────────
	do-ip4: yes
	do-ip6: ${do_ip6}
	do-udp: yes
	do-tcp: yes
	deny-any: yes

	# ── Controle de acesso ───────────────────────────────────────────
	# Loopbacks IPv4
	access-control: 127.0.0.1/32        allow
	access-control: ${DNS_LO_IPV4_1}/32 allow
	access-control: ${DNS_LO_IPV4_2}/32 allow
	# Faixa do AS (ajuste a máscara conforme seu bloco)
	access-control: ${ipv4_address}/22  allow
	# Redes privadas / CGNAT
	access-control: 100.64.0.0/10       allow
	access-control: 192.168.0.0/16      allow
	access-control: 172.16.0.0/12       allow
	access-control: 10.0.0.0/8          allow
	# Bloqueio padrão IPv4
	access-control: 0.0.0.0/0           refuse
${acl_ipv6}
	# ── Clientes adicionais ──────────────────────────────────────────
	# access-control: X.X.X.X/X allow

	# ── Performance (auto-tuning via nproc) ──────────────────────────
	verbosity: 1
	statistics-interval: 0
	statistics-cumulative: no
	extended-statistics: yes
	num-threads: ${UNBOUND_THREADS}

	outgoing-range: 8192
	outgoing-num-tcp: 1024
	incoming-num-tcp: 2048
	so-rcvbuf: 4m
	so-sndbuf: 4m

	edns-buffer-size: 1232
	msg-cache-size: 3G
	msg-cache-slabs: ${UNBOUND_SLABS}
	num-queries-per-thread: 4096
	rrset-cache-size: 2G
	rrset-cache-slabs: ${UNBOUND_SLABS}
	infra-cache-slabs: ${UNBOUND_SLABS}
	key-cache-slabs: ${UNBOUND_SLABS}

	# ── Identidade e caminhos ────────────────────────────────────────
	chroot: ""
	username: "unbound"
	directory: "/etc/unbound"
	logfile: "/var/log/unbound/unbound.log"
	use-syslog: no
	log-time-ascii: yes
	log-queries: no
	pidfile: "/var/run/unbound.pid"

	# ── Resolução ────────────────────────────────────────────────────
	root-hints: "/etc/unbound/named.cache"
	hide-identity: yes
	hide-version: yes
	unwanted-reply-threshold: 10000000
	prefetch: yes
	prefetch-key: yes
	rrset-roundrobin: yes
	minimal-responses: yes

	# ── DNSSEC ───────────────────────────────────────────────────────
	module-config: "respip validator iterator"
	val-clean-additional: yes
	val-log-level: 1

	# ── Blocklist ────────────────────────────────────────────────────
	include: /etc/unbound/bloqueio.conf

# ── Zona raiz autoritativa (mais seguro que root-hints puro) ─────────────────
auth-zone:
	name: "."
	master: "b.root-servers.net"
	master: "c.root-servers.net"
	master: "f.root-servers.net"
	master: "g.root-servers.net"
	master: "k.root-servers.net"
	master: "lax.xfr.dns.icann.org"
	master: "iad.xfr.dns.icann.org"
	fallback-enabled: yes
	for-downstream: no
	for-upstream: yes
	zonefile: "/var/lib/unbound/root.zone"
EOF

    step "Habilitando Unbound..." systemctl enable unbound > /dev/null 2>&1
}

# =============================================================================
# SEÇÃO 13 — RESOLV.CONF PERSISTENTE
# =============================================================================

configure_resolv() {
    head "RESOLV.CONF — PERSISTÊNCIA"

    backup_file "/etc/resolv.conf"

    # Remove possível link simbólico do systemd-resolved
    rm -f /etc/resolv.conf

    {
        echo "# Gerenciado por setup_trixie.sh — NÃO EDITAR MANUALMENTE"
        echo "nameserver 127.0.0.1"
        if $HAS_IPV6; then echo "nameserver ::1"; fi
        echo "options edns0 trust-ad"
    } > /etc/resolv.conf

    # Previne sobrescrita pelo dhclient
    if [[ -f /etc/dhcp/dhclient.conf ]]; then
        if ! grep -q "supersede domain-name-servers" /etc/dhcp/dhclient.conf; then
            step "Configurando dhclient para não sobrescrever DNS..." \
                bash -c "echo 'supersede domain-name-servers 127.0.0.1;' \
                    >> /etc/dhcp/dhclient.conf"
        fi
    fi
}

# =============================================================================
# SEÇÃO 14 — BGP (FRR 10.x)
# =============================================================================

configure_bgp() {
    head "BGP — FRR 10.x"

    if [[ "$ASN" == "00000" ]]; then
        info "ASN '00000' — configuração BGP ignorada."
        return 0
    fi

    backup_file "/etc/frr/frr.conf"
    backup_file "/etc/frr/daemons"

    # Ativa bgpd e vtysh de forma idempotente
    step "Ativando bgpd..." \
        sed -i 's/^bgpd=no$/bgpd=yes/' /etc/frr/daemons

    if ! grep -q "^vtysh_enable=yes" /etc/frr/daemons; then
        sed -i 's/^vtysh_enable=no$/vtysh_enable=yes/' /etc/frr/daemons \
            || echo "vtysh_enable=yes" >> /etc/frr/daemons
    fi

    # Monta configuração em arquivo temporário antes de escrever no frr.conf
    # Usa cat com heredoc sem expansão de variável especial ($asn etc)
    # para preservar indentação exata requerida pelo FRR
    local tmp_frr
    tmp_frr=$(mktemp)

    # IPv6 no BGP — condicional
    local v6_neighbor="" v6_af=""
    if $HAS_IPV6; then
        v6_neighbor=" neighbor ${ipv6_gateway} remote-as ${ASN}
 neighbor ${ipv6_gateway} description IBGP-V6
 !"
        v6_af="
 !
 address-family ipv6 unicast
  redistribute kernel
  redistribute connected
  redistribute static
  neighbor ${ipv6_gateway} activate
  neighbor ${ipv6_gateway} prefix-list IBGP-V6-IN in
  neighbor ${ipv6_gateway} prefix-list IBGP-V6-OUT out
 exit-address-family"
    fi

    local v6_prefix_lists=""
    if $HAS_IPV6; then
        v6_prefix_lists="
!
ipv6 prefix-list IBGP-V6-IN seq 10 deny any
ipv6 prefix-list IBGP-V6-OUT seq 10 permit ${DNS_LO_IPV6_1}/128 le 128
ipv6 prefix-list IBGP-V6-OUT seq 20 permit ${DNS_LO_IPV6_2}/128 le 128
ipv6 prefix-list IBGP-V6-OUT seq 999 deny any"
    fi

    # Escreve em tmp primeiro — preserva indentação e não usa echo com $var
    cat > "$tmp_frr" << FRRCONF
!
! Gerado por setup_trixie.sh v${VERSION}
!
router bgp ${ASN}
 bgp router-id ${ipv4_address}
 no bgp ebgp-requires-policy
 neighbor ${ipv4_gateway} remote-as ${ASN}
 neighbor ${ipv4_gateway} description IBGP-V4
 !
${v6_neighbor}
 address-family ipv4 unicast
  redistribute kernel
  redistribute connected
  redistribute static
  neighbor ${ipv4_gateway} prefix-list IBGP-V4-IN in
  neighbor ${ipv4_gateway} prefix-list IBGP-V4-OUT out
 exit-address-family${v6_af}
exit
!
ip prefix-list IBGP-V4-IN seq 10 deny any
ip prefix-list IBGP-V4-OUT seq 10 permit ${DNS_LO_IPV4_1}/32 le 32
ip prefix-list IBGP-V4-OUT seq 20 permit ${DNS_LO_IPV4_2}/32 le 32
ip prefix-list IBGP-V4-OUT seq 999 deny any${v6_prefix_lists}
!
end
FRRCONF

    step "Escrevendo frr.conf..." bash -c "cat '$tmp_frr' >> /etc/frr/frr.conf"
    rm -f "$tmp_frr"

    step "Reiniciando FRR..." systemctl restart frr.service
}

# =============================================================================
# SEÇÃO 17 — VERIFICAÇÃO FINAL
# =============================================================================

check_services() {
    head "VERIFICAÇÃO FINAL DE SERVIÇOS"

    local all_ok=true
    local services=(unbound ntpsec irqbalance)
    [[ "$ASN" != "00000" ]] && services+=(frr)

    printf "  %-25s %-10s %s\n" "SERVIÇO" "STATUS" "PID"
    printf "  %s\n" "$(printf '─%.0s' {1..50})"

    for svc in "${services[@]}"; do
        local status pid
        status=$(systemctl is-active "$svc" 2>/dev/null || echo "inativo")
        pid=$(systemctl show "$svc" --property=MainPID --value 2>/dev/null || echo "-")
        if [[ "$status" == "active" ]]; then
            printf "  %-25s ${GREEN}%-10s${RESET} %s\n" "$svc" "$status" "$pid"
        else
            printf "  %-25s ${RED}%-10s${RESET} %s\n" "$svc" "$status" "-"
            all_ok=false
        fi
    done

    # Teste rápido de resolução DNS
    printf "\n"
    _log STEP "Teste DNS (dig @127.0.0.1 google.com)..."
    if dig +short +time=3 @127.0.0.1 google.com A > /dev/null 2>&1; then
        _log PASS
    else
        _log WARN
        warn "DNS não está respondendo ainda — pode precisar de alguns segundos"
    fi

    # Mostra timer
    _log STEP "Verificando timer da blocklist..."
    if systemctl is-active --quiet "$TIMER_UNIT"; then
        _log PASS
    else
        _log WARN
    fi

    printf "\n"
    info "Log completo de instalação: ${LOG_FILE}"
    info "Backups dos arquivos originais: ${BACKUP_DIR}"

    if ! $all_ok; then
        warn "Serviço(s) inativo(s). Diagnóstico: journalctl -xe --no-pager | tail -50"
    fi
}

# =============================================================================
# MAIN — FLUXO PRINCIPAL
# =============================================================================

main() {
    # Inicialização
    parse_args "$@"
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    printf "\n${BOLD}${CYAN}"
    printf "╔══════════════════════════════════════════════════════╗\n"
    printf "║  Setup ISP — Unbound + FRR  │  Debian 13 Trixie     ║\n"
    printf "║  Versão %-44s║\n" "${VERSION}"
    printf "╚══════════════════════════════════════════════════════╝\n"
    printf "${RESET}\n"

    info "Log: $LOG_FILE"

    check_root
    check_debian_trixie
    init_backup
    install_bootstrap   # Precisa vir antes do whiptail
    collect_network_info
    collect_asn

    configure_loopbacks
    configure_repos
    configure_kernel
    configure_grub
    update_system
    install_packages
    configure_unbound
    configure_resolv
    configure_bgp

    check_services

}

main "$@"