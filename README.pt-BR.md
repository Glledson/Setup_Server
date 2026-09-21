<div align="center">

# ⚙️ Setup Server

**Automação de provisionamento e infraestrutura para servidores ISP.**

![Debian](https://img.shields.io/badge/Debian-13%20Trixie-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-333333?style=for-the-badge&logo=linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-2F80ED?style=for-the-badge)

[![Typing SVG](https://readme-typing-svg.demolab.com?font=Fira+Code&size=20&pause=1000&color=4EAA25&center=true&vCenter=true&width=650&lines=Provisione+servidores+ISP+em+minutos;DNS+%C2%B7+Monitoramento+%C2%B7+FTP+%C2%B7+Hardening+SSH;Um+comando.+Zero+repeti%C3%A7%C3%A3o.)](https://git.io/typing-svg)

![GitHub last commit](https://img.shields.io/github/last-commit/Glledson/Setup_Server?style=flat-square&color=orange)
![GitHub issues](https://img.shields.io/github/issues/Glledson/Setup_Server?style=flat-square&color=red)
![Maintained](https://img.shields.io/badge/Maintained%3F-yes-brightgreen?style=flat-square)

*Transforme uma instalação nova do Debian 13 em um servidor ISP endurecido, monitorado e pronto para produção — com um comando.*

[**Instalação**](#-instalação) · [**Serviços**](#-catálogo-de-serviços) · [**Arquitetura**](#-arquitetura) · [**Contribuição**](#-contribuição)

🌐 [**English (EN)**](README.md) · [**Português (PT-BR)**](README.pt-BR.md)

</div>

---

## 🚀 Resumo

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Glledson/Setup_Server/main/install.sh)"
```

Execute como `root` em um Debian 13 limpo, escolha o que precisar no menu interativo e receba um servidor endurecido e monitorado. Detalhes abaixo. ⬇️

---

## 📋 Sumário

| | | |
|---|---|---|
| [🔎 Visão Geral](#-visão-geral) | [🏗️ Arquitetura](#-arquitetura) | [🔄 Fluxo de Provisionamento](#-fluxo-de-provisionamento) |
| [✨ Funcionalidades](#-funcionalidades) | [🧩 Catálogo de Serviços](#-catálogo-de-serviços) | [🖥️ Interface Interativa](#-interface-interativa) |
| [📦 Instalação](#-instalação) | [⚙️ Configuração](#%EF%B8%8F-configuração) | [🧩 Adicionar um Serviço](#-adicionar-um-serviço) |
| [📝 Logs](#-logs) | [✅ Requisitos](#-requisitos) | [⚠️ Considerações Operacionais](#-considerações-operacionais) |
| [🧭 Princípios de Design](#-princípios-de-design) | [🗺️ Roadmap](#-roadmap) | [🤝 Contribuição](#-contribuição) |
| [🔒 Segurança](#-segurança) | [📄 Licença](#-licença) | |

---

## 🔎 Visão Geral

Implantar um servidor de produção vai além de instalar um SO. Este projeto automatiza as partes repetitivas desse processo:

✅ Configuração de repositórios e atualizações (Trixie)
✅ Instalação de pacotes essenciais
✅ Endurecimento (hardening) do SSH, banners e gerenciamento de chaves
✅ Customização do ambiente administrativo (vim, bash, aliases)
✅ Monitoramento com Zabbix + Grafana
✅ Infraestrutura DNS recursivo com Unbound + FRR (BGP)
✅ Servidor FTP com Pure-FTPd + MariaDB

Fazer isso manualmente em dezenas de servidores não escala — **o Setup Server transforma isso em um fluxo repetível, de um comando.**

> O objetivo não é substituir o julgamento do administrador — é automatizar as partes repetitivas e bem definidas para que os engenheiros foquem nas decisões que realmente importam.

---

## 🏗️ Arquitetura

<details>
<summary><b>Clique para expandir a árvore de diretórios</b></summary>

```text
Setup_Server/
│
├── config/
│   ├── issue.net
│   ├── sources.list.trixie
│   └── vimrc
│
├── lib/
│   ├── common.sh
│   └── ssh_utils.sh
│
├── scripts/
│   ├── 01-base-system.sh
│   ├── 02-ssh-security.sh
│   │
│   └── services/
│       ├── dns-recursivo.sh
│       ├── ftp.sh
│       └── monitoring.sh
│
├── LICENSE
├── README.md
├── README.pt-BR.md
├── install.sh
└── setup_server.sh
```

</details>

| Caminho | Finalidade |
|---|---|
| 📁 `config/` | Templates de configuração e arquivos do sistema |
| 📁 `lib/` | Funções Bash reutilizáveis entre os módulos |
| 📁 `scripts/` | Estágios numerados de preparação do sistema |
| 📁 `scripts/services/` | Um script isolado por serviço |
| 🎛️ `setup_server.sh` | Orquestrador interativo baseado em `dialog` |
| 🥾 `install.sh` | Script de bootstrap (one-liner) |

O orquestrador carrega (`source`) os módulos de `lib/` e os estágios numerados de `scripts/`, mantendo apenas a lógica de menu e despacho de serviços. Cada serviço é um script standalone em `scripts/services/`, executado como subprocesso.

---

## 🔄 Fluxo de Provisionamento

```text
                     Instalação do Debian
                             │
                             ▼
                  ┌─────────────────────┐
                  │    Setup Server     │
                  └──────────┬──────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
      Preparação        Segurança de      Configuração
      do Sistema         Acesso              do
      (01-base)          (02-ssh)          Ambiente
           │                 │
           └────────┬────────┘
                    ▼
          Provisionamento de Serviços
                    │
        ┌───────────┬───────────┐
        ▼           ▼           ▼
   Monitoramento  DNS Recursivo    FTP
   Zabbix+Graf   Unbound+FRR    Pure-FTPd
                     │
                     ▼
          Servidor em Produção
```

O administrador sempre mantém o controle sobre quais componentes entram em cada servidor.

---

## ✨ Funcionalidades

### 🖥️ Preparação do Sistema
Configuração de APT para Debian 13 (Trixie) · atualização completa · utilitários administrativos · configuração do Vim · customização do shell root — uma base consistente em todos os servidores.

### 🔐 Configuração SSH
| Configuração | Valor |
|---|---|
| Protocolo | Apenas SSH 2 |
| Login root | `PermitRootLogin prohibit-password` |
| Porta personalizada | `SSH_PORT` (padrão **`29019`**) |
| Banner do Debian | Desabilitado |
| Banner pré-autenticação | Habilitado |
| Validação | `sshd -t` antes de cada reinício |

> ⚠️ **Atenção:** confirme que a nova porta SSH está liberada no firewall *antes* de aplicar isso remotamente — ninguém quer ficar trancado para fora de um servidor a quilômetros de distância.

### 🛠️ Ambiente Administrativo
`fzf` · `grc` · `bash-completion` · saída colorida · aliases customizados de `ls`/rede · prompt padronizado.

### 🔑 Gerenciamento de Chaves SSH
Adiciona sua chave pública em `/root/.ssh/authorized_keys` com as permissões corretas. A chave pode ser informada de forma interativa ou via variável de ambiente `SSH_PUB_KEY`.

> 🔒 **Nota de segurança:** nenhuma chave está embutida no repositório. Sempre revise e rotacione as chaves conforme a política da sua organização.

### 🪧 Banners de Login
- **Pré-autenticação:** `/etc/issue.net` exibe o aviso de acesso antes do login.
- **Pós-autenticação:** script dinâmico imprime hostname, IP local, data/hora e o aviso de acesso a cada login.

---

## 🧩 Catálogo de Serviços

| Serviço | Script | Tecnologia / Finalidade |
|---|---|---|
| 📊 Monitoramento | `scripts/services/monitoring.sh` | Zabbix (server + Agent 2) + Grafana |
| 🌐 DNS Recursivo | `scripts/services/dns-recursivo.sh` | Unbound + FRR (BGP) |
| 🗂️ FTP | `scripts/services/ftp.sh` | Pure-FTPd com backend MariaDB |

Modular por design — basta adicionar um script standalone em `scripts/services/` e registrá-lo no menu do `setup_server.sh`.

---

## 🖥️ Interface Interativa

```text
UP-ISP :: Setup do servidor

[ ] SOURCES
[ ] UPDATE
[ ] SSH
[ ] PACOTES
[ ] BASHCOMP
[ ] VIM
[ ] BASHRC
[ ] SSHKEY
[ ] BANNERPRE
[ ] BANNERPOS
[ ] SERVICOS
[ ] LIMPEZA
```

Uma ferramenta, vários papéis de servidor:

```text
🌐 Servidor DNS       📊 Servidor de Monitoramento   🗂️ Servidor FTP
└── DNS Recursivo     └── Zabbix + Grafana          └── Pure-FTPd + MariaDB
    (Unbound + FRR)
```

---

## 📦 Instalação

**⚡ One-liner** (Debian limpo, execute como `root`):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Glledson/Setup_Server/main/install.sh)"
```

**🔧 Manual:**

```bash
git clone https://github.com/Glledson/Setup_Server.git
cd Setup_Server
chmod +x setup_server.sh
./setup_server.sh
```

---

## ⚙️ Configuração

O comportamento pode ser ajustado por variáveis de ambiente, sem editar os scripts:

| Variável | Padrão | Usado por | Finalidade |
|---|---|---|---|
| `SSH_PUB_KEY` | *(prompt interativo)* | Chave SSH | Chave pública adicionada em `/root/.ssh/authorized_keys` |
| `SSH_PORT` | `29019` | Config. SSH | Porta SSH personalizada |
| `DB_PASS` | `ZABBIX-UPISP` | Monitoramento / FTP | Senha do Zabbix / usuário do banco do FTP |
| `GRAFANA_VERSION` | `12.0.0` | Monitoramento | Versão do `.deb` do Grafana |
| `DB_ROOT_PASS` | `FTP-UPISP` | FTP | Senha do MariaDB (use a mesma do Monitoramento em caso de coexistência) |
| `FTP_PASS` | `FTP-UPISP` | FTP | Senha padrão das contas FTP semeadas |
| `FTP_BASE_DIR` | `/var/pure-ftpd` | FTP | Diretório base das contas FTP |

> ⚠️ **Sempre** defina um `DB_PASS` forte em produção (o padrão existe apenas para provisionamento).
> O serviço `dns-recursivo.sh` também aceita flags de CLI: `--no-reboot`, `--skip-bgp`, `--asn XXXXX` e a variável `CLIENT_NET=CIDR` (rede de clientes; padrão: auto a partir da interface principal).

---

<details>
<summary><b>🧾 Atalhos rápidos</b></summary>

| Tarefa | Comando |
|---|---|
| Executar o setup completo | `./setup_server.sh` |
| Instalar apenas um serviço | `bash scripts/services/monitoring.sh` |
| Acompanhar o último provisionamento | `tail -f /var/log/upisp-setup.log` |
| Validar a configuração SSH manualmente | `sshd -t` |
| Verificar se a porta SSH personalizada está ouvindo | `ss -tlnp \| grep ${SSH_PORT:-29019}` |

</details>

## 📝 Logs

| Log | Caminho |
|---|---|
| Log principal do provisionamento | `/var/log/upisp-setup.log` |
| Log temporário do APT | `/tmp/upisp-apt.log` |

---

## ✅ Requisitos

- Debian 13 (Trixie)
- Privilégios de root
- Conexão com a internet
- `apt` · `bash` · `systemd` · `dialog`

Alguns módulos de serviço têm dependências extras — confira o script em `scripts/services/`.

---

## 🧩 Adicionar um Serviço

1. Crie `scripts/services/<serviço>.sh` como script **standalone** (`#!/bin/bash`, `set -euo pipefail`). Importe `lib/common.sh` se quiser os helpers de log compartilhados.
2. Teste localmente: `bash scripts/services/<serviço>.sh`
3. Registre no `setup_server.sh`:
   - adicione a entrada na lista do `dialog --checklist`
   - mapeie em `instalar_servicos()`: `case "NOME") instalar_servico "$SCRIPT_DIR/scripts/services/<serviço>.sh" "NOME" ;;`
4. Adicione o serviço ao [Catálogo de Serviços](#-catálogo-de-serviços) com sua finalidade e portas expostas.

---

## ⚠️ Considerações Operacionais

O Setup Server faz alterações **em nível de sistema**. Antes de executar em produção, revise:

- Acesso SSH e regras de firewall
- Repositórios APT
- Chaves SSH do root
- Configuração de rede e portas de serviços
- Serviços/configurações existentes que possam conflitar

> 🧪 **Teste em staging primeiro.** Sempre.

---

## 🧭 Princípios de Design

| Princípio | O que significa aqui |
|---|---|
| 🔁 **Reprodutibilidade** | Mesmo procedimento → mesma base, toda vez |
| 🧩 **Modularidade** | Serviços independentes do núcleo |
| 👁️ **Transparência** | Toda mudança é identificável e registrada |
| 🛠️ **Manutenibilidade** | Simples o suficiente para qualquer engenheiro de infra estender |
| ⚙️ **Eficiência Operacional** | Automatize o repetitivo — nunca esconda uma decisão |

---

## 🗺️ Roadmap

- [ ] Perfis de instalação
- [ ] Modo de provisionamento não interativo
- [ ] Gerenciamento de dependências entre serviços
- [x] Validação pós-instalação
- [x] Tratamento de erros aprimorado
- [ ] Relatórios de provisionamento
- [ ] Rollback de configuração
- [ ] Configuração centralizada de serviços
- [ ] Catálogo de serviços expandido
- [x] Suporte Debian 13 (Trixie)
- [ ] Testes de compatibilidade com Debian 14
- [ ] Modo de fallback para Debian 12 (Bookworm)
- [ ] Arquitetura de plugins modulares

---

## 🤝 Contribuição

Contribuições são bem-vindas! Novos módulos de serviço devem seguir o padrão modular existente:

1. Defina claramente os requisitos do serviço
2. Mantenha a lógica específica isolada
3. Valide a configuração antes de reiniciar qualquer serviço
4. Forneça logs estruturados e significativos
5. Evite valores hardcoded específicos do ambiente
6. Documente requisitos e portas expostas

---

## 🔒 Segurança

Executa com **privilégios de root** e pode tocar em componentes críticos do SO. Sempre revise o código antes de executar scripts vindos de local externo:

- Configuração SSH
- Definições de repositórios
- Configuração de serviços e portas de rede
- Qualquer comando privilegiado

> 🚫 **Nunca execute um script não revisado diretamente contra infraestrutura crítica de produção.**

---

## 📄 Licença

Distribuído sob **Licença MIT**. Consulte o texto completo em [`LICENSE`](LICENSE).

---

<div align="center">

**Setup Server**
*Provisionamento de infraestrutura para ambientes ISP.*

`Linux` · `Networking` · `Automation` · `Infrastructure` · `ISP`

</div>