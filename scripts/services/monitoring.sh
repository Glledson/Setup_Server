#!/bin/bash
# scripts/services/monitoring.sh — Instalação e configuração Zabbix + Grafana
# Autor: Gledsom Oliveira
# Versão: 1.2 (paths corrigidos, senhas configuráveis)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

DB_PASS="${DB_PASS:-ZABBIX-UPISP}"
GRAFANA_VERSION="${GRAFANA_VERSION:-12.0.0}"

# ─────────────────────────────────────────────────────────────
# 1. Validação e dependências
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}>>> Validação inicial...${RESET}"
apt-get update -y > /dev/null 2>&1
apt-get install -y sudo curl wget gnupg2 musl libfontconfig1 adduser > /dev/null 2>&1
echo -e "${GREEN}OK${RESET}"

# ─────────────────────────────────────────────────────────────
# 2. Repositórios Zabbix e Grafana
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}>>> Configurando repositórios...${RESET}"

wget -q https://repo.zabbix.com/zabbix/7.4/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.4+debian13_all.deb
dpkg -i zabbix-release_latest_7.4+debian13_all.deb
rm -f zabbix-release_latest_7.4+debian13_all.deb
echo -e "${GREEN}Zabbix repo OK${RESET}"

wget -q "https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}+security~01_amd64.deb"
dpkg -i "grafana_${GRAFANA_VERSION}+security~01_amd64.deb"
rm -f "grafana_${GRAFANA_VERSION}+security~01_amd64.deb"
echo -e "${GREEN}Grafana repo OK${RESET}"

# ─────────────────────────────────────────────────────────────
# 3. Atualização do sistema
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}>>> Atualizando pacotes do sistema...${RESET}"
apt-get update -y > /dev/null 2>&1
apt-get upgrade -y > /dev/null 2>&1
apt-get dist-upgrade -y > /dev/null 2>&1
echo -e "${GREEN}OK${RESET}"

# ─────────────────────────────────────────────────────────────
# 4. Instalação de pacotes
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}>>> Instalando serviços...${RESET}"
pacotes=(
    zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf
    zabbix-sql-scripts zabbix-agent2
    adduser libfontconfig1 musl
    certbot python3-certbot-apache
    mariadb-server mariadb-client
    apache2 apache2-utils libapache2-mod-php
    php php-mysql php-cli php-pear php-gmp php-gd
    php-bcmath php-mbstring php-curl php-xml php-zip
)
for pacote in "${pacotes[@]}"; do
    echo -ne "Verificando/Instalando: $pacote... "
    if dpkg -s "$pacote" > /dev/null 2>&1; then
        echo -e "${GREEN}Já instalado${RESET}"
    else
        if apt-get install -y "$pacote" > /dev/null 2>&1; then
            echo -e "${GREEN}OK${RESET}"
        else
            echo -e "${RED}FAIL${RESET}"
        fi
    fi
done

# ─────────────────────────────────────────────────────────────
# 5. Apache e PHP para Zabbix
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}>>> Configurando Apache e PHP para Zabbix...${RESET}"
a2enmod rewrite > /dev/null 2>&1
a2enmod headers > /dev/null 2>&1

cp /etc/apache2/sites-enabled/000-default.conf /etc/apache2/sites-enabled/000-default.conf.bak
cat > /etc/apache2/sites-enabled/000-default.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /usr/share/zabbix/ui

    <Directory /usr/share/zabbix/ui>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/zabbix_error.log
    CustomLog \${APACHE_LOG_DIR}/zabbix_access.log combined
</VirtualHost>
EOF
echo -e "${GREEN}OK${RESET}"

sed -i 's/ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf
sed -i 's/ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf
systemctl restart apache2
echo -e "${GREEN}Apache OK${RESET}"

# ─────────────────────────────────────────────────────────────
# 6. MariaDB para Zabbix
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}>>> Configurando MariaDB para Zabbix...${RESET}"

echo -ne "Configurando credenciais... "
mariadb -u root <<EOF
USE mysql;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
EOF
echo -e "${GREEN}OK${RESET}"

echo -ne "Importando esquema Zabbix... "
zcat /usr/share/zabbix/ui/sql-scripts/mysql/server.sql.gz \
    | mysql --default-character-set=utf8mb4 -uzabbix -p"${DB_PASS}" zabbix
echo -e "${GREEN}OK${RESET}"

mariadb -u root -p"${DB_PASS}" <<EOF
SET GLOBAL log_bin_trust_function_creators = 0;
EOF

# ─────────────────────────────────────────────────────────────
# 7. PHP tuning
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}>>> Configurando PHP para Zabbix...${RESET}"
sed -i 's/post_max_size = .*/post_max_size = 32M/' /etc/php/*/apache2/php.ini
sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/*/apache2/php.ini
sed -i 's/max_input_time = .*/max_input_time = 300/' /etc/php/*/apache2/php.ini
echo -e "${GREEN}OK${RESET}"

# ─────────────────────────────────────────────────────────────
# 8. Zabbix Server
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}>>> Configurando Zabbix Server...${RESET}"
sed -i "s/# DBPassword=/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_server.conf
echo -e "${GREEN}OK${RESET}"

systemctl restart zabbix-server zabbix-agent2 apache2
echo -e "${GREEN}Zabbix Server + Agent + Apache reiniciados${RESET}"

echo -e "\n${GREEN}>>> Configuração do monitoring concluída com sucesso!${RESET}"
