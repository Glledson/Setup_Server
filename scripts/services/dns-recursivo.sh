#!/bin/bash
# =============================================================================
# Script de Provisionamento: DNS Recursivo (Unbound) + BGP (FRR)
# Compatível com: Debian 13 "Trixie" (kernel 6.12 LTS, systemd 257, FRR 10.3)
# Versão: 3.1
# =============================================================================
# USO: bash setup_trixie.sh [--no-reboot] [--skip-bgp] [--asn XXXXX]
# =============================================================================

set -uo pipefail

# =============================================================================
# CONSTANTES E CONFIGURAÇÕES GLOBAIS
# =============================================================================

readonly RUN_TS=$(date +%Y%m%d_%H%M%S)
readonly VERSION="3.1-$(date +%Y%m%d)"
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/var/log/setup_trixie_${RUN_TS}.log"
readonly SCRIPT_BLOCKLIST="/usr/local/bin/bloqueio_unbound.sh"
readonly BACKUP_DIR="/root/setup_backup_${RUN_TS}"

# IPs fixos dos loopbacks DNS
readonly DNS_LO_IPV4_1="10.10.10.10"
readonly DNS_LO_IPV4_2="10.10.11.11"
readonly DNS_LO_IPV6_1="fc00::10:10:10:10"
readonly DNS_LO_IPV6_2="fc00::10:10:11:11"

# Flags de controle
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
    echo "[$ts] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

info()  { _log INFO  "$*"; }
ok()    { _log OK    "$*"; }
warn()  { _log WARN  "$*"; }
error() { _log ERROR "$*"; }
head()  { _log HEAD  "$*"; }

step() {
    local desc="$1"; shift
    _log STEP "$desc"
    local output
    local rc=0
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
            --skip-bgp)   OPT_ASN="00000" ;;
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
        local codename pretty
        codename=$(grep -Po '(?<=^VERSION_CODENAME=).+' /etc/os-release | tr -d '"' || true)
        pretty=$(grep -Po '(?<=^PRETTY_NAME=).+' /etc/os-release | tr -d '"' || true)
        if [[ "${codename:-}" != "trixie" ]]; then
            warn "Sistema detectado: ${pretty:-desconhecido}"
            warn "Este script foi otimizado para Debian 13 Trixie."
        fi
    fi
}

init_backup() {
    mkdir -p "$BACKUP_DIR"
    info "Backups de arquivos originais em: $BACKUP_DIR"
}

backup_file() {
    local file="$1"
    [[ -f "$file" ]] && cp -p "$file" "$BACKUP_DIR/$(basename "$file").bak" 2>/dev/null || true
}

# =============================================================================
# SEÇÃO 1 — COLETA DE INFORMAÇÕES DE REDE E ASN
# =============================================================================

collect_network_info() {
    head "DETECÇÃO DE REDE"

    local route_output
    route_output=$(ip route show 2>/dev/null) || true

    PRIMARY_IF=""
    PRIMARY_IF=$(echo "$route_output" | awk '/^default/ {print $5; exit}')
    if [[ -z "$PRIMARY_IF" ]]; then
        PRIMARY_IF=$(ip -4 addr show 2>/dev/null \
            | awk '/^[0-9]+:/ && !/loopback/ {gsub(":",""); print $2; exit}')
    fi
    if [[ -z "$PRIMARY_IF" ]]; then
        die "Não foi possível detectar a interface de rede primária."
    fi

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
        if command -v python3 &>/dev/null; then
            IPV6_PREFIX=$(python3 -c "
import ipaddress, sys
try:
    net = ipaddress.IPv6Network('${ipv6_address}/64', strict=False)
    print(str(net))
except Exception:
    sys.exit(1)
" 2>/dev/null) || IPV6_PREFIX=""
        fi
        if [[ -z "$IPV6_PREFIX" ]]; then
            IPV6_PREFIX=$(echo "$ipv6_address" | awk -F: '{printf "%s:%s:%s:%s::/64\n",$1,$2,$3,$4}')
        fi
    else
        warn "IPv6 não detectado — configurações IPv6 serão omitidas."
    fi

    CPU_CORES=$(nproc 2>/dev/null || echo 1)
    UNBOUND_THREADS=$(( CPU_CORES > 8 ? 8 : CPU_CORES ))

    local s=1
    while (( s < UNBOUND_THREADS )); do s=$(( s * 2 )); done
    UNBOUND_SLABS=$(( s > 8 ? 8 : s ))

    info "Interface : $PRIMARY_IF"
    info "IPv4      : $ipv4_address  |  GW: $ipv4_gateway"
    if $HAS_IPV6; then
        info "IPv6      : $ipv6_address  |  GW: $ipv6_gateway  |  Prefixo: $IPV6_PREFIX"
    fi
    info "CPUs      : $CPU_CORES  |  Threads Unbound: $UNBOUND_THREADS  |  Slabs: $UNBOUND_SLABS"
}

collect_asn() {
    head "CONFIGURAÇÃO DO ASN"

    if [[ -n "$OPT_ASN" ]]; then
        [[ "$OPT_ASN" =~ ^[0-9]+$ ]] || die "ASN inválido via --asn: '$OPT_ASN'"
        ASN="$OPT_ASN"
        [[ "$ASN" == "00000" ]] \
            && info "BGP desativado (ASN=00000)" \
            || info "ASN definido via argumento: $ASN"
        return
    fi

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

install_bootstrap() {
    head "DEPENDÊNCIAS INICIAIS"
    step "Instalando whiptail, curl, wget, lsb-release..." \
        apt-get install -y whiptail curl wget lsb-release ca-certificates gnupg > /dev/null 2>&1
}

# =============================================================================
# SEÇÃO 2 — CONFIGURAÇÕES DE REDE E REPOSITÓRIOS
# =============================================================================

configure_loopbacks() {
    head "INTERFACES DE LOOPBACK"
    backup_file "/etc/network/interfaces.d/loopback.conf"

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

    step_soft "Subindo lo:0..." ifup lo:0 2>/dev/null
    step_soft "Subindo lo:1..." ifup lo:1 2>/dev/null

    for ip in "$DNS_LO_IPV4_1" "$DNS_LO_IPV4_2"; do
        if ip addr show lo | grep -q "$ip"; then
            ok "Loopback $ip ativo"
        else
            warn "Loopback $ip não detectado — será ativado no próximo boot"
        fi
    done
}

configure_repos() {
    head "REPOSITÓRIOS EXTRAS (FRR UPSTREAM)"
    local codename
    codename=$(lsb_release -sc 2>/dev/null || echo "trixie")

    step "Importando chave GPG do FRRouting..." \
        bash -c "curl -fsSL https://deb.frrouting.org/frr/keys.gpg \
            | tee /usr/share/keyrings/frrouting.gpg > /dev/null"

    step "Adicionando repositório FRR (${codename} frr-stable)..." \
        bash -c "echo 'deb [signed-by=/usr/share/keyrings/frrouting.gpg] \
https://deb.frrouting.org/frr ${codename} frr-stable' \
            > /etc/apt/sources.list.d/frr.list"
}

configure_kernel() {
    head "PARÂMETROS DE KERNEL (SYSCTL)"

    cat > /etc/sysctl.d/99-isp-tuning.conf << 'SYSCTL'
# ISP Tuning — setup_trixie.sh
vm.swappiness=10
vm.vfs_cache_pressure=50

net.core.rmem_max=2147483647
net.core.wmem_max=2147483647
net.ipv4.tcp_rmem=4096 87380 2147483647
net.ipv4.tcp_wmem=4096 65536 2147483647

net.netfilter.nf_conntrack_buckets=512000
net.netfilter.nf_conntrack_max=10000000

net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1

net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
SYSCTL

    local mod_conf="/etc/modules-load.d/conntrack.conf"
    if ! grep -q "^nf_conntrack$" "$mod_conf" 2>/dev/null; then
        echo "nf_conntrack" >> "$mod_conf"
    fi

    step "Carregando nf_conntrack..." modprobe nf_conntrack
    step "Aplicando sysctl (sysctl --system)..." bash -c "sysctl --system > /dev/null 2>&1"
}

configure_grub() {
    head "GRUB — DESATIVAR APPARMOR"

    mkdir -p /etc/default/grub.d
    cat > /etc/default/grub.d/99-apparmor-off.cfg << 'GRUB'
# Desativa AppArmor — setup_trixie.sh
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=0"
GRUB

    step "Atualizando GRUB..." bash -c "update-grub > /dev/null 2>&1"
}

update_system() {
    head "ATUALIZAÇÃO DO SISTEMA"
    step "Atualizando listas do APT..." apt-get update > /dev/null 2>&1
    step "Aplicando pacotes atualizados..." apt-get dist-upgrade -y > /dev/null 2>&1
}

install_packages() {
    head "INSTALAÇÃO DE PACOTES"

    local pacotes=(
        unbound irqbalance bash-completion ntpsec curl gnupg rsync
        dnsutils bind9-dnsutils dnstop ethtool net-tools frr frr-doc
        frr-pythontools frr-rpki-rtrlib python3
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

configure_ntp() {
    head "CONFIGURAÇÃO DE HORA (NTPSEC)"
    backup_file "/etc/ntpsec/ntp.conf"

    cat > /etc/ntpsec/ntp.conf << 'NTP'
# Configuração NTPsec para ISPs
driftfile /var/lib/ntpsec/ntp.drift
leapfile /usr/share/zoneinfo/leap-seconds.list

server a.st1.ntp.br iburst
server b.st1.ntp.br iburst
server c.st1.ntp.br iburst
server d.st1.ntp.br iburst
server 200.160.7.186 iburst

restrict default kod nomodify nopeer noquery limited
restrict 127.0.0.1
restrict ::1
NTP

    step "Reiniciando NTPsec..." systemctl restart ntpsec
}

# =============================================================================
# SEÇÃO 3 — SERVIÇOS (UNBOUND, BLOCKLIST, BGP)
# =============================================================================

configure_unbound() {
    head "UNBOUND — CONFIGURAÇÃO"

    mkdir -p /var/log/unbound /var/lib/unbound
    touch /var/log/unbound/unbound.log /etc/unbound/bloqueio.conf
    chown -R unbound:unbound /var/log/unbound/ /var/lib/unbound/

    step "Baixando root hints (HTTPS)..." \
        wget -q -O /etc/unbound/named.cache https://www.internic.net/domain/named.cache

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
    access-control: ::1/128 allow
    access-control: ${DNS_LO_IPV6_1}/128 allow
    access-control: ${DNS_LO_IPV6_2}/128 allow
    access-control: ${IPV6_PREFIX} allow
    access-control: ::/0 refuse"
    fi

    cat > /etc/unbound/unbound.conf.d/upisp.conf << EOF
server:
    interface: 127.0.0.1
    interface: ${DNS_LO_IPV4_1}
    interface: ${DNS_LO_IPV4_2}${iface_ipv6}
    interface-automatic: no

    outgoing-interface: ${ipv4_address}${outgoing_ipv6}

    do-ip4: yes
    do-ip6: ${do_ip6}
    do-udp: yes
    do-tcp: yes
    deny-any: yes

    access-control: 127.0.0.1/32        allow
    access-control: ${DNS_LO_IPV4_1}/32 allow
    access-control: ${DNS_LO_IPV4_2}/32 allow
    access-control: ${ipv4_address}/22  allow
    access-control: 100.64.0.0/10       allow
    access-control: 192.168.0.0/16      allow
    access-control: 172.16.0.0/12       allow
    access-control: 10.0.0.0/8          allow
    access-control: 0.0.0.0/0           refuse
${acl_ipv6}

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

    chroot: ""
    username: "unbound"
    directory: "/etc/unbound"
    logfile: "/var/log/unbound/unbound.log"
    use-syslog: no
    log-time-ascii: yes
    log-queries: no
    pidfile: "/var/run/unbound.pid"

    root-hints: "/etc/unbound/named.cache"
    hide-identity: yes
    hide-version: yes
    unwanted-reply-threshold: 10000000
    prefetch: yes
    prefetch-key: yes
    rrset-roundrobin: yes
    minimal-responses: yes

    module-config: "respip validator iterator"
    val-clean-additional: yes
    val-log-level: 1

    include: /etc/unbound/bloqueio.conf

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
    step "Iniciando Unbound..." systemctl restart unbound
}

configure_resolv() {
    head "RESOLV.CONF — PERSISTÊNCIA"
    backup_file "/etc/resolv.conf"
    rm -f /etc/resolv.conf

    {
        echo "# Gerenciado por setup_trixie.sh"
        echo "nameserver 127.0.0.1"
        if $HAS_IPV6; then echo "nameserver ::1"; fi
        echo "options edns0 trust-ad"
    } > /etc/resolv.conf

    if [[ -f /etc/dhcp/dhclient.conf ]]; then
        if ! grep -q "supersede domain-name-servers" /etc/dhcp/dhclient.conf; then
            echo 'supersede domain-name-servers 127.0.0.1;' >> /etc/dhcp/dhclient.conf
        fi
    fi
}

configure_bgp() {
    head "BGP — FRR 10.x"

    if [[ "$ASN" == "00000" ]]; then
        info "ASN '00000' — configuração BGP ignorada."
        return 0
    fi

    backup_file "/etc/frr/frr.conf"
    backup_file "/etc/frr/daemons"

    sed -i 's/^bgpd=no$/bgpd=yes/' /etc/frr/daemons

    if ! grep -q "^vtysh_enable=yes" /etc/frr/daemons; then
        sed -i 's/^vtysh_enable=no$/vtysh_enable=yes/' /etc/frr/daemons \
            || echo "vtysh_enable=yes" >> /etc/frr/daemons
    fi

    local tmp_frr
    tmp_frr=$(mktemp)

    local v6_neighbor="" v6_af="" v6_prefix_lists=""
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

        v6_prefix_lists="
!
ipv6 prefix-list IBGP-V6-IN seq 10 deny any
ipv6 prefix-list IBGP-V6-OUT seq 10 permit ${DNS_LO_IPV6_1}/128 le 128
ipv6 prefix-list IBGP-V6-OUT seq 20 permit ${DNS_LO_IPV6_2}/128 le 128
ipv6 prefix-list IBGP-V6-OUT seq 999 deny any"
    fi

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

    step "Escrevendo frr.conf..." bash -c "cat '$tmp_frr' > /etc/frr/frr.conf"
    rm -f "$tmp_frr"

    step "Reiniciando FRR..." systemctl restart frr.service
}

# =============================================================================
# SEÇÃO 4 — VERIFICAÇÃO FINAL E REBOOT
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

    printf "\n"
    _log STEP "Teste DNS (dig @127.0.0.1 google.com)..."
    if dig +short +time=3 @127.0.0.1 google.com A > /dev/null 2>&1; then
        _log PASS
    else
        _log WARN
        warn "DNS não está respondendo ainda — aguarde alguns segundos."
    fi


    printf "\n"
    info "Log completo de instalação: ${LOG_FILE}"
    info "Backups dos arquivos originais: ${BACKUP_DIR}"

    if ! $all_ok; then
        warn "Serviço(s) inativo(s). Diagnóstico: journalctl -xe --no-pager | tail -50"
    fi
}

do_reboot() {
    head "FINALIZAÇÃO"
    if $OPT_REBOOT; then
        info "O sistema será reiniciado em 10 segundos para aplicar os parâmetros de kernel e rede."
        info "Pressione Ctrl+C para cancelar o reboot."
        sleep 10
        reboot
    else
        info "Opção --no-reboot detectada. Reinicialização automática pulada."
    fi
}

# =============================================================================
# MAIN — FLUXO PRINCIPAL
# =============================================================================

main() {
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
    install_bootstrap
    collect_network_info
    collect_asn

    configure_loopbacks
    configure_repos
    configure_kernel
    configure_grub
    update_system
    install_packages
    configure_ntp
    configure_unbound
    configure_resolv
    configure_bgp

    check_services
    do_reboot
}

main "$@"