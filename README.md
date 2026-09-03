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
