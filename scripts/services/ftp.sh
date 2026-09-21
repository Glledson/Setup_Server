#!/bin/bash

# =========================================================================================== #
# Script de Instalação e Configuração FTP com Pure-FTPd e MariaDB                             #
# Autor: Gledsom Oliveira                                                                     #
# Data: 19-12-2025                                                                            #
# Versão: 1.1                                                                                 #
# Descrição: Instala e configura um servidor FTP seguro usando Pure-FTPd com backend MariaDB. #
# =========================================================================================== #

# Configurações de Variáveis (todas sobrescrevíveis via ambiente)
DB_ROOT_PASS="${DB_ROOT_PASS:-FTP-UPISP}"   # senha root do MariaDB — use a mesma do monitoring.sh em caso de coexistência
DB_NAME="${DB_NAME:-pureftpd}"
DB_USER="${DB_USER:-pureftpd}"
DB_PASS="${DB_PASS:-$DB_ROOT_PASS}"              # senha do usuário do banco
FTP_PASS="${FTP_PASS:-FTP-UPISP}"                # senha padrão das contas FTP semeadas
FTP_UID_GID="${FTP_UID_GID:-2001}"
FTP_BASE_DIR="${FTP_BASE_DIR:-/var/pure-ftpd}"
SSL_PATH="${SSL_PATH:-/etc/ssl/private}"

# Cores para o output
GREEN="\e[32m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

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
apt-get install sudo curl wget gnupg2 -y > /dev/null 2>&1
exibir_resultado $?


# 2. Atualização Geral do Sistema
echo -e "${BLUE}>>> Atualizando pacotes do sistema (isso pode demorar)...${RESET}"
apt-get upgrade -y > /dev/null 2>&1
apt-get dist-upgrade -y > /dev/null 2>&1
exibir_resultado $?

# 3. Instalação de Serviços
pacotes=("mariadb-server" "mariadb-client" "pure-ftpd-mysql")
for pacote in "${pacotes[@]}"; do
    echo -ne "Verificando/Instalando: $pacote... "
    if dpkg -s "$pacote" > /dev/null 2>&1; then
        echo -e "${GREEN}Já instalado${RESET}"
    else
        apt-get install -y "$pacote" > /dev/null 2>&1
        exibir_resultado $?
    fi
done

# 4. Configuração de Segurança MariaDB
echo -ne "Configurando credenciais do MariaDB... "
MYSQL_ROOT=(mariadb -u root)
if ! mariadb -u root -e 'SELECT 1' > /dev/null 2>&1; then
    MYSQL_ROOT=(mariadb -u root -p"${DB_ROOT_PASS}")
fi
"${MYSQL_ROOT[@]}" <<EOF
USE mysql;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
FLUSH PRIVILEGES;
EOF
if [ $? -ne 0 ]; then
    echo
    printf "${RED}Falha de autenticação no MariaDB. Confira DB_ROOT_PASS (deve ser a senha root atual — igual à do monitoring.sh se coexistirem).${RESET}\n"
    exit 1
fi
echo -e "${GREEN}OK${RESET}"

# 5. Usuário de Sistema para FTP
echo -ne "Criando usuário/grupo de sistema (ftpgroup)... "
groupadd -g $FTP_UID_GID ftpgroup 2>/dev/null
useradd -u $FTP_UID_GID -s /bin/false -d /dev/null -c "pureftpd user" -g ftpgroup ftpuser 2>/dev/null
mkdir -p "$FTP_BASE_DIR"
sed -i "s/^UPLOADUID=.*/UPLOADUID=$FTP_UID_GID/" /etc/default/pure-ftpd-common
sed -i "s/^UPLOADGID=.*/UPLOADGID=$FTP_UID_GID/" /etc/default/pure-ftpd-common
exibir_resultado $?

# 6. Banco de Dados e Tabelas
echo -ne "Provisionando banco de dados pureftpd... "
"${MYSQL_ROOT[@]}" <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP ON ${DB_NAME}.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP ON ${DB_NAME}.* TO '${DB_USER}'@'localhost.localdomain' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
USE ${DB_NAME};
CREATE TABLE IF NOT EXISTS ftpd (
    User varchar(16) NOT NULL default '',
    status enum('0','1') NOT NULL default '0',
    Password varchar(64) NOT NULL default '',
    Uid varchar(11) NOT NULL default '-1',
    Gid varchar(11) NOT NULL default '-1',
    Dir varchar(128) NOT NULL default '',
    ULBandwidth smallint(5) NOT NULL default '0',
    DLBandwidth smallint(5) NOT NULL default '0',
    comment tinytext NOT NULL,
    ipaccess varchar(15) NOT NULL default '*',
    QuotaSize smallint(5) NOT NULL default '0',
    QuotaFiles int(11) NOT NULL default 0,
    PRIMARY KEY (User),
    UNIQUE KEY User (User)
);
EOF
exibir_resultado $?

# 7. Integração Pure-FTPd + MySQL
echo -ne "Configurando arquivo de conexão mysql.conf... "
[ -f /etc/pure-ftpd/db/mysql.conf ] && mv /etc/pure-ftpd/db/mysql.conf /etc/pure-ftpd/db/mysql.conf_orig
cat <<EOF > /etc/pure-ftpd/db/mysql.conf
MYSQLSocket /var/run/mysqld/mysqld.sock
MYSQLUser $DB_USER
MYSQLPassword $DB_PASS
MYSQLDatabase $DB_NAME
MYSQLCrypt md5
MYSQLGetPW SELECT Password FROM ftpd WHERE User="\L" AND status="1" AND (ipaccess = "*" OR ipaccess LIKE "\R")
MYSQLGetUID SELECT Uid FROM ftpd WHERE User="\L" AND status="1" AND (ipaccess = "*" OR ipaccess LIKE "\R")
MYSQLGetGID SELECT Gid FROM ftpd WHERE User="\L" AND status="1" AND (ipaccess = "*" OR ipaccess LIKE "\R")
MYSQLGetDir SELECT Dir FROM ftpd WHERE User="\L" AND status="1" AND (ipaccess = "*" OR ipaccess LIKE "\R")
MySQLGetBandwidthUL SELECT ULBandwidth FROM ftpd WHERE User="\L" AND status="1" AND (ipaccess = "*" OR ipaccess LIKE "\R")
MySQLGetBandwidthDL SELECT DLBandwidth FROM ftpd WHERE User="\L" AND status="1" AND (ipaccess = "*" OR ipaccess LIKE "\R")
MySQLGetQTASZ SELECT QuotaSize FROM ftpd WHERE User="\L" AND status="1" AND (ipaccess = "*" OR ipaccess LIKE "\R")
MySQLGetQTAFS SELECT QuotaFiles FROM ftpd WHERE User="\L" AND status="1" AND (ipaccess = "*" OR ipaccess LIKE "\R")
EOF
chmod 600 /etc/pure-ftpd/db/mysql.conf
exibir_resultado $?

# 8. Certificados SSL e DHParam
echo -ne "Gerando certificados SSL/TLS (OpenSSL)... "
openssl dhparam -out /etc/ssl/private/pure-ftpd-dhparams.pem 2048 > /dev/null 2>&1
openssl req -x509 -nodes -newkey rsa:2048 -sha256 \
    -keyout $SSL_PATH/pure-ftpd.pem \
    -out $SSL_PATH/pure-ftpd.pem \
    -subj "/CN=pure-ftpd" > /dev/null 2>&1
chmod 600 $SSL_PATH/*.pem
exibir_resultado $?

# 9. Ajustes Finais Pure-FTPd (Segurança)
echo -ne "Aplicando políticas de segurança (Chroot/TLS)... "
echo "yes" > /etc/pure-ftpd/conf/ChrootEveryone
echo "yes" > /etc/pure-ftpd/conf/CreateHomeDir
echo "1" > /etc/pure-ftpd/conf/TLS
echo "HIGH" > /etc/pure-ftpd/conf/TLSCipherSuite
exibir_resultado $?

# 10. Inserção de Usuários Padrão e Diretórios
echo -ne "Criando contas padrão e diretórios FTP... "
for entry in "ftp-mk:mk" "ftp-sw:sw" "ftp-bgp:bgp" "ftp-olt:olt" "ftp-erp:erp" "ftp-srv:srv"; do
    user="${entry%%:*}"
    subdir="${entry##*:}"
    mkdir -p "${FTP_BASE_DIR}/${subdir}"
    chown "${FTP_UID_GID}:${FTP_UID_GID}" "${FTP_BASE_DIR}/${subdir}"
    "${MYSQL_ROOT[@]}" -e "USE ${DB_NAME}; INSERT IGNORE INTO ftpd (User, status, Password, Uid, Gid, Dir) VALUES ('${user}', '1', MD5('${FTP_PASS}'), '${FTP_UID_GID}', '${FTP_UID_GID}', '${FTP_BASE_DIR}/${subdir}');" > /dev/null 2>&1
done
exibir_resultado $?

# Finalização
echo -ne "Habilitando e reiniciando pure-ftpd-mysql... "
systemctl enable pure-ftpd-mysql > /dev/null 2>&1
systemctl restart pure-ftpd-mysql
exibir_resultado $?

echo -e "${GREEN}"
echo "Configuração concluída com sucesso!"
echo "--------------------------------------------------------------"
echo " Serviço : pure-ftpd-mysql ($(systemctl is-active pure-ftpd-mysql 2>/dev/null))"
echo " Banco   : ${DB_NAME} | usuário: ${DB_USER}"
echo " Base    : ${FTP_BASE_DIR}"
echo " Contas semeadas: ftp-mk, ftp-sw, ftp-bgp, ftp-olt, ftp-erp, ftp-srv"
echo " Senha padrão das contas: ${FTP_PASS}  (MD5 armazenado)"
echo " Ajuste contas em: mariadb -u root -p${DB_ROOT_PASS} ${DB_NAME}"
echo "   UPDATE ftpd SET Password=MD5('NOVA') WHERE User='ftp-mk';"
echo "--------------------------------------------------------------"
echo -e "${RESET}"