Você está sem armazenamento há 21 dias … O armazenamento é insuficiente. Não é possível salvar no Drive, fazer backup no Google Fotos nem usar o Gmail. Aproveite 30 GB de armazenamento pagando R$ 1 por 3 meses R$ 4,50.
100%
#!/bin/bash
set -euo pipefail

# =========================================================================================== #
# Script de Instalação e Configuração Zabbix + Grafana                                        #
# Autor: Gledsom Oliveira                                                                     #
# Data: 07-01-2026                                                                            #
# Versão: 1.1                                                                                 #
# Descrição: Instala e configura um servidor Zabbix + Grafana                                 #
# =========================================================================================== #

# Cores para o output
GREEN="\e[32m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

# Configurações de Variáveis
DB_ROOT_PASS="  "

# Função para exibir o resultado da operação
exibir_resultado() {
    if [ $1 -eq 0 ]; then
        printf "${GREEN}OK${RESET}\n"
    else
        printf "${RED}FAIL${RESET}\n"
        exit 1 # Interrompe o script em falhas críticas
    fi
}

# 1. Validação e Instalação de Dependências
echo -e "${BLUE}>>> Iniciando Validação Inicial...${RESET}"
apt-get update -y > /dev/null 2>&1
apt-get install sudo curl wget gnupg2 musl libfontconfig1 adduser -y > /dev/null 2>&1
exibir_resultado $?

# 2. Configuração dos repositórios
echo -e "${BLUE}>>> Configurando repositórios...${RESET}"

# Repositório Zabbix-7.4 para Debian 13
wget https://repo.zabbix.com/zabbix/7.4/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.4+debian13_all.deb
dpkg -i zabbix-release_latest_7.4+debian13_all.deb
exibir_resultado $?

# Repositório Grafana
wget https://dl.grafana.com/oss/release/grafana_12.0.0+security~01_amd64.deb
dpkg -i grafana_12.0.0+security~01_amd64.deb
exibir_resultado $?

# 3. Atualização Geral do Sistema
echo -e "${BLUE}>>> Atualizando pacotes do sistema (isso pode demorar)...${RESET}"
apt-get update -y > /dev/null 2>&1
apt-get upgrade -y > /dev/null 2>&1
apt-get dist-upgrade -y > /dev/null 2>&1
exibir_resultado $?

# 3. Instalação de Serviços
pacotes=(
  "zabbix-server-mysql"
  "zabbix-frontend-php"
  "zabbix-apache-conf"
  "zabbix-sql-scripts"
  "zabbix-agent2"

  "adduser"
  "libfontconfig1"
  "musl"

  "certbot"
  "python3-certbot-apache"

  "mariadb-server"
  "mariadb-client"

  "apache2"
  "apache2-utils"
  "libapache2-mod-php"

  "php"
  "php-mysql"
  "php-cli"
  "php-pear"
  "php-gmp"
  "php-gd"
  "php-bcmath"
  "php-mbstring"
  "php-curl"
  "php-xml"
  "php-zip"
)
for pacote in "${pacotes[@]}"; do
    echo -ne "Verificando/Instalando: $pacote... "
    if dpkg -s "$pacote" > /dev/null 2>&1; then
        echo -e "${GREEN}Já instalado${RESET}"
    else
        apt-get install -y "$pacote" > /dev/null 2>&1
        exibir_resultado $?
    fi
done

# 4. Configuração do Apache e PHP para Zabbix
echo -e "${BLUE}>>> Configurando Apache e PHP para Zabbix...${RESET}"
a2enmod rewrite ; a2enmod headers
cp /etc/apache2/sites-enabled/000-default.conf /etc/apache2/sites-enabled/000-default.conf.bak
cat <<EOF > /etc/apache2/sites-enabled/000-default.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot usr/share/zabbix/ui

    <Directory usr/share/zabbix/ui>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/zabbix_error.log
    CustomLog \${APACHE_LOG_DIR}/zabbix_access.log combined
</VirtualHost>
EOF
exibir_resultado $?

sed -i 's/ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf
sed -i 's/ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf
systemctl restart apache2
exibir_resultado $?

# 5. Configuração do Banco de Dados MariaDB para Zabbix
echo -e "${BLUE}>>> Configurando Banco de Dados MariaDB para Zabbix...${RESET}"
echo -ne "Configurando credenciais do MariaDB... "
mariadb -u root  <<EOF
USE mysql;
ALTER USER 'root'@'localhost' IDENTIFIED BY 'ZABBIX-UPISP';
FLUSH PRIVILEGES;
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'ZABBIX-UPISP';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
EOF
exibir_resultado $?

echo -ne "Importando esquema inicial e dados para o Zabbix... "
zcat usr/share/zabbix/ui/sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p"ZABBIX-UPISP" zabbix
exibir_resultado $?

mariadb -u root -p"ZABBIX-UPISP" <<EOF
SET GLOBAL log_bin_trust_function_creators = 0;
EOF

# 6. Configuração do PHP para Zabbix
echo -e "${BLUE}>>> Configurando PHP para Zabbix...${RESET}"
sed -i 's/post_max_size = .*/post_max_size = 32M/' /etc/php/*/apache2/php.ini
sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/*/apache2/php.ini
sed -i 's/max_input_time = 60/max_input_time = 300/' /etc/php/*     /apache2/php.ini

# 7. Configuração do Zabbix Server  
echo -e "${BLUE}>>> Configurando Zabbix Server...${RESET}"
sed -i "s/# DBPassword=/DBPassword=ZABBIX-UPISP/" /etc/zabbix/zabbix_server.conf
exibir_resultado $?
systemctl restart zabbix-server zabbix-agent2 apache2
exibir_resultado $?

# Finalização
echo -e "${GREEN}>>> Configuração finalizada com sucesso!${RESET}"
echo -e "${RED}Removendo script em 3 segundos...${RESET}"
sleep 3
rm -- "$0"