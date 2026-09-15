<div align="center">

# ⚙️ Setup Server

**Server provisioning and infrastructure automation for ISP environments.**

![Debian](https://img.shields.io/badge/Debian-13%20Trixie-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-333333?style=for-the-badge&logo=linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-2F80ED?style=for-the-badge)

[![Typing SVG](https://readme-typing-svg.demolab.com?font=Fira+Code&size=20&pause=1000&color=4EAA25&center=true&vCenter=true&width=650&lines=Provision+Debian+ISP+servers+in+minutes;DNS+%C2%B7+Monitoring+%C2%B7+SSH+hardening;One+command.+Zero+repetition.)](https://git.io/typing-svg)

![GitHub last commit](https://img.shields.io/github/last-commit/Glledson/Setup_Server?style=flat-square&color=orange)
![GitHub issues](https://img.shields.io/github/issues/Glledson/Setup_Server?style=flat-square&color=red)
![Maintained](https://img.shields.io/badge/Maintained%3F-yes-brightgreen?style=flat-square)

*Turn a fresh Debian 13 install into a hardened, monitored, production-ready ISP server — with one command.*

[**Install**](#-installation) · [**Services**](#-service-catalog) · [**Architecture**](#-architecture) · [**Contributing**](#-contributing)

🌐 [**English**](README.md) · [**Português (PT-BR)**](README.pt-BR.md)

</div>

---

## 🚀 TL;DR

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Glledson/Setup_Server/main/install.sh)"
```

Run it as `root` on a clean Debian 13 box, pick what you need from the interactive menu, and walk away with a hardened, monitored server. Full details below. ⬇️

---

## 📋 Table of Contents

| | | |
|---|---|---|
| [🔎 Overview](#-overview) | [🏗️ Architecture](#-architecture) | [🔄 Provisioning Workflow](#-provisioning-workflow) |
| [✨ Features](#-features) | [🧩 Service Catalog](#-service-catalog) | [🖥️ Interactive Interface](#-interactive-interface) |
| [📦 Installation](#-installation) | [⚙️ Configuration](#%EF%B8%8F-configuration) | [🧩 Adding a Service](#-adding-a-service) |
| [📝 Logging](#-logging) | [✅ Requirements](#-requirements) | [⚠️ Operational Considerations](#-operational-considerations) |
| [🧭 Design Principles](#-design-principles) | [🗺️ Roadmap](#-roadmap) | [🤝 Contributing](#-contributing) |
| [🔒 Security](#-security) | [📄 License](#-license) | |

---

## 🔎 Overview

Deploying a production server involves more than installing an OS. This toolkit automates the repetitive parts of that process:

✅ System updates & Trixie repository configuration
✅ Essential package installation
✅ SSH hardening, banners & key management
✅ Administrative environment customization (vim, bash, aliases)
✅ Monitoring with Zabbix + Grafana
✅ DNS recursive infrastructure with Unbound + FRR (BGP)

Doing this by hand across dozens of servers doesn't scale — **Setup Server turns it into a repeatable, one-command workflow.**

> The goal isn't to replace administrative judgment — it's to automate the repetitive, well-defined parts so engineers can focus on the decisions that actually matter.

---

## 🏗️ Architecture

<details>
<summary><b>Click to expand the directory tree</b></summary>

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
│       └── monitoring.sh
│
├── LICENSE
├── README.md
├── README.pt-BR.md
├── install.sh
└── setup_server.sh
```

</details>

| Path | Purpose |
|------|---------|
| 📁 `config/` | Configuration templates & system-level files |
| 📁 `lib/` | Reusable Bash functions shared across modules |
| 📁 `scripts/` | Numbered core system-preparation stages |
| 📁 `scripts/services/` | One isolated standalone script per service |
| 🎛️ `setup_server.sh` | Interactive `dialog`-based orchestrator |
| 🥾 `install.sh` | One-line bootstrap script |

The orchestrator sources `lib/` and the numbered `scripts/` stages, keeping only the menu and service dispatch logic. Each service is a standalone script under `scripts/services/` invoked as a subprocess.

---

## 🔄 Provisioning Workflow

```text
                     Debian Installation
                             │
                             ▼
                  ┌─────────────────────┐
                  │    Setup Server     │
                  └──────────┬──────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
      System            Access            Environment
    Preparation         Security          Configuration
    (01-base)           (02-ssh)
           │                 │
           └────────┬────────┘
                    ▼
          Service Provisioning
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   Monitoring             DNS Recursive
   Zabbix + Grafana       Unbound + FRR
                    │
                    ▼
           Operational Server
```

The administrator always stays in control of which components go on which server.

---

## ✨ Features

### 🖥️ System Preparation
APT setup for Debian 13 (Trixie) · full upgrade · admin utilities · Vim config · root shell customization — a consistent baseline on every box.

### 🔐 SSH Configuration
| Setting | Value |
|---|---|
| Protocol | SSH 2 only |
| Root login | `PermitRootLogin prohibit-password` |
| Custom port | `SSH_PORT` (default **`29019`**) |
| Debian banner | Disabled |
| Pre-auth banner | Enabled |
| Validation | `sshd -t` before every restart |

> ⚠️ **Heads up:** confirm the new SSH port is allowed by your firewall *before* applying this remotely — nobody wants to get locked out of a box three states away.

### 🛠️ Administrative Environment
`fzf` · `grc` · `bash-completion` · colored output · custom `ls`/network aliases · standardized prompt.

### 🔑 SSH Key Management
Adds your public key to `/root/.ssh/authorized_keys` with correct permissions. The key can be provided interactively or via the `SSH_PUB_KEY` environment variable.

> 🔒 **Security note:** no keys are embedded in the repository. Always review and rotate access keys per your org's access-control policy.

### 🪧 Login Banners
- **Pre-auth:** `/etc/issue.net` shows an access notice before login.
- **Post-auth:** dynamic profile script prints hostname, local IP, date/time, and an access notice on every login.

---

## 🧩 Service Catalog

| Service | Script | Technology / Purpose |
|---|---|---|
| 📊 Monitoring | `scripts/services/monitoring.sh` | Zabbix (server + Agent 2) + Grafana |
| 🌐 DNS Recursive | `scripts/services/dns-recursivo.sh` | Unbound + FRR (BGP) |

Modular by design — drop a new standalone script into `scripts/services/` and register it in the service menu of `setup_server.sh`.

---

## 🖥️ Interactive Interface

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

One tool, many server roles:

```text
🌐 DNS Server        📊 Monitoring Server
└── DNS Recursive    └── Zabbix + Grafana
    (Unbound + FRR)
```

---

## 📦 Installation

**⚡ One-liner** (clean Debian, run as `root`):

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

## ⚙️ Configuration

Behavior can be adjusted through environment variables, without editing the scripts:

| Variable | Default | Used by | Purpose |
|---|---|---|---|
| `SSH_PUB_KEY` | *(interactive prompt)* | SSH key | Public key added to `/root/.ssh/authorized_keys` |
| `SSH_PORT` | `29019` | SSH config | Custom SSH port |
| `DB_PASS` | `ZABBIX-UPISP` | Monitoring | Zabbix / MariaDB password |
| `GRAFANA_VERSION` | `12.0.0` | Monitoring | Grafana `.deb` version |

> ⚠️ **Always** set a strong `DB_PASS` on production deployments (default is meant for provisioning only).
> The `dns-recursivo.sh` service also accepts CLI flags: `--no-reboot`, `--skip-bgp`, `--asn XXXXX`.

---

<details>
<summary><b>🧾 Quick command cheatsheet</b></summary>

| Task | Command |
|---|---|
| Run full interactive setup | `./setup_server.sh` |
| Install only one service | `bash scripts/services/monitoring.sh` |
| Check the last provisioning run | `tail -f /var/log/upisp-setup.log` |
| Validate SSH config manually | `sshd -t` |
| Check the custom SSH port is listening | `ss -tlnp \| grep ${SSH_PORT:-29019}` |

</details>

## 📝 Logging

| Log | Path |
|---|---|
| Main provisioning log | `/var/log/upisp-setup.log` |
| Temporary APT log | `/tmp/upisp-apt.log` |

---

## ✅ Requirements

- Debian 13 (Trixie)
- Root privileges
- Internet connectivity
- `apt` · `bash` · `systemd` · `dialog`

Some service modules have extra dependencies — check the script under `scripts/services/`.

---

## 🧩 Adding a Service

1. Create `scripts/services/<service>.sh` as a **standalone** script (`#!/bin/bash`, `set -euo pipefail`). Source `lib/common.sh` when you want shared logging helpers.
2. Test it locally: `bash scripts/services/<service>.sh`
3. Register it in `setup_server.sh`:
   - add the entry to the `dialog --checklist` list
   - map it in `instalar_servicos()`: `case "NAME") instalar_servico "$SCRIPT_DIR/scripts/services/<service>.sh" "NAME" ;;`
4. Add the service to the [Service Catalog](#-service-catalog) with its purpose and any exposed ports.

---

## ⚠️ Operational Considerations

Setup Server makes **system-level changes**. Before running against production, review:

- SSH access & firewall rules
- APT repositories
- Root SSH keys
- Network configuration & service ports
- Existing services/configs that could conflict

> 🧪 **Test in staging first.** Always.

---

## 🧭 Design Principles

| Principle | What it means here |
|---|---|
| 🔁 **Reproducibility** | Same procedure → same baseline, every time |
| 🧩 **Modularity** | Services stay independent from the core |
| 👁️ **Transparency** | Every change is identifiable and logged |
| 🛠️ **Maintainability** | Simple enough for any infra engineer to extend |
| ⚙️ **Operational Efficiency** | Automate the repetitive — never hide a decision |

---

## 🗺️ Roadmap

- [ ] Installation profiles
- [ ] Non-interactive provisioning mode
- [ ] Service dependency management
- [x] Post-installation validation
- [x] Improved error handling
- [ ] Provisioning reports
- [ ] Configuration rollback
- [ ] Centralized service configuration
- [ ] Expanded ISP service catalog
- [x] Debian 13 (Trixie) support
- [ ] Debian 14 forward-compatibility testing
- [ ] Legacy Debian 12 (Bookworm) fallback mode
- [ ] Modular plugin architecture

---

## 🤝 Contributing

Contributions welcome! New service modules should follow the existing modular pattern:

1. Clearly define the service's requirements
2. Keep service-specific logic isolated
3. Validate config before restarting any service
4. Provide meaningful, structured logging
5. Avoid hard-coded environment-specific values
6. Document requirements and exposed ports

---

## 🔒 Security

Runs with **root privileges** and can touch critical OS components. Always review the source before running scripts from an external location:

- SSH configuration
- Repository definitions
- Service configuration & network ports
- Any privileged command

> 🚫 **Never run an unreviewed script directly against critical production infrastructure.**

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for the full text.

---

<div align="center">

**Setup Server**
*Infrastructure provisioning for ISP environments.*

`Linux` · `Networking` · `Automation` · `Infrastructure` · `ISP`

</div>