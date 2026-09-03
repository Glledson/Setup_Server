# Server Setup Engine

> Automation framework for base hardening, system provisioning, and infrastructure service deployment on Debian-based Linux servers.

![Debian](https://img.shields.io/badge/Debian-13%20(Trixie)-A81D33?style=flat-square&logo=debian&logoColor=white)
![Shell Script](https://img.shields.io/badge/Shell_Script-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)

---

## 📋 Visão Geral

O **Setup_Server** é um orquestrador modular desenvolvido para padronizar a preparação inicial de servidores em ambientes de Provedores de Internet (ISPs) e infraestrutura de TI. 

Através de uma interface interativa em Ncurses (`dialog`) ou via linha de comando, ele automatiza atualizações de repositórios, *hardening* do serviço SSH, personalização do terminal root, gerenciamento de chaves e a implantação de serviços essenciais de rede.

---

## 🚀 Instalação e Execução Rápida

Execute o comando abaixo diretamente no servidor recém-instalado (requer privilégios de `root`):

```bash
bash -c "$(curl -fsSL [https://raw.githubusercontent.com/Glledson/Setup_Server/main/install.sh](https://raw.githubusercontent.com/Glledson/Setup_Server/main/install.sh))"


🛠️ Funcionalidades Principais
System Base Hardening: Atualização de repositórios, remoção de pacotes desnecessários e otimização do kernel via sysctl.

SSH Hardening: Configuração segura de portas, desabilitação de login via senha/root direto e imposição de autenticação por chave pública.

Ambiente CLI Customizado: Terminal Root otimizado com vim, alias úteis, prompt informativo (PS1) e suporte ao issue.net.

Módulos de Serviços de Rede:

DNS: Resoluções recursivas e autoritativas (Unbound / BIND9).

Monitoramento & Métricas: Zabbix Agent 2, Graylog Stack e ferramentas de telemetria.

Gestão de ISP: phpIPAM, Krill (RPKI), ferramentas de teste de banda (nperf, speedtest, minha-conexao) e Smokeping.

📂 Arquitetura do Projeto
Plaintext
├── config/             # Templates de configuracao (sources.list, issue.net, vimrc)
├── lib/                # Bibliotecas auxiliares (common.sh, ssh_utils.sh)
├── scripts/            # Modulos de execucao sequencial (01-base, 02-ssh)
│   └── services/       # Scripts de implantacao de servicos especificos
├── install.sh          # Bootstrap e verificador de dependencias
└── setup_server.sh     # Core orquestrador e interface Ncurses (dialog)
📌 Requisitos
Sistema Operacional: Debian 12 (Bookworm) ou Debian 13 (Trixie).

Acesso: Privilégios de superusuário (root).

Conectividade: Acesso à internet para download dos pacotes e repositórios.
EOF