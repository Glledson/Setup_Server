<div align="center">

# ⚙️ Setup Server

**Server provisioning and infrastructure automation for ISP environments.**

![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-333333?style=for-the-badge&logo=linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-2F80ED?style=for-the-badge)

![GitHub last commit](https://img.shields.io/github/last-commit/Glledson/Setup_Server?style=flat-square&color=orange)
![GitHub stars](https://img.shields.io/github/stars/Glledson/Setup_Server?style=flat-square&color=yellow)
![GitHub issues](https://img.shields.io/github/issues/Glledson/Setup_Server?style=flat-square&color=red)
![Maintained](https://img.shields.io/badge/Maintained%3F-yes-brightgreen?style=flat-square)

*Turn a fresh Debian install into a fully hardened, monitored, production-ready ISP server — with one command.*

[**Install**](#-installation) · [**Services**](#-service-catalog) · [**Architecture**](#-architecture) · [**Contributing**](#-contributing)

</div>

---

### 🚀 TL;DR

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Glledson/Setup_Server/main/install.sh)"
```

Run it as `root` on a clean Debian 12 box, pick what you need from the interactive menu, and walk away with a hardened, monitored server. Full details below. ⬇️

---

## 📋 Table of Contents

| | | |
|---|---|---|
| [🔎 Overview](#-overview) | [🏗️ Architecture](#-architecture) | [🔄 Provisioning Workflow](#-provisioning-workflow) |
| [✨ Features](#-features) | [🧩 Service Catalog](#-service-catalog) | [🖥️ Interactive Interface](#-interactive-interface) |
| [📦 Installation](#-installation) | [📝 Logging](#-logging) | [✅ Requirements](#-requirements) |
| [⚠️ Operational Considerations](#-operational-considerations) | [🧭 Design Principles](#-design-principles) | [🗺️ Roadmap](#-roadmap) |
| [🤝 Contributing](#-contributing) | [🔒 Security](#-security) | [📄 License](#-license) |

---

## 🔎 Overview

Deploying a production server involves more than installing an OS. A typical provisioning run means:

✅ System updates & repository configuration
✅ Essential package installation
✅ SSH hardening & access control
✅ Administrative environment customization
✅ Monitoring & network diagnostics
✅ DNS infrastructure
✅ Time synchronization
✅ Logging
✅ IP address management
✅ RPKI infrastructure
✅ Performance testing services

Doing this by hand across dozens of servers doesn't scale — **Setup Server turns it into a repeatable, one-command workflow.**

> The goal isn't to replace administrative judgment — it's to automate the repetitive, well-defined parts so engineers can focus on the decisions that actually matter.

---

## 🏗️ Architecture

<details>
<summary><b>Click to expand the directory tree</b></summary>

```text
setup_server/
│
├── config/
│   ├── issue.net
│   ├── sources.list.bookworm
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
│       ├── dns-reverso.sh
│       ├── ftp.sh
│       ├── graylog.sh
│       ├── krill.sh
│       ├── minha-conexao.sh
│       ├── monitoring.sh
│       ├── nperf.sh
│       ├── ntp.sh
│       ├── phpipam.sh
│       ├── smokeping.sh
│       └── speedtest.sh
│
├── install.sh
├── setup_server.sh
└── README.md
```

</details>

| Path | Purpose |
|------|---------|
| 📁 `config/` | Configuration templates & system-level files |
| 📁 `lib/` | Reusable Bash functions shared across modules |
| 📁 `scripts/` | Numbered core system-preparation stages |
| 📁 `scripts/services/` | One isolated script per service |
| 🎛️ `setup_server.sh` | Interactive `dialog`-based orchestrator |
| 🥾 `install.sh` | One-line bootstrap script |

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
       System             Access          Environment
     Preparation         Security         Configuration
          │                 │                 │
          └─────────────────┼─────────────────┘
                            │
                            ▼
                    Service Provisioning
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
         DNS           Monitoring          Logging
          │                 │                 │
          ▼                 ▼                 ▼
     Infrastructure     Operations        Observability
                            │
                            ▼
                    Operational Server
```

The administrator always stays in control of which components go on which server.

---

## ✨ Features

### 🖥️ System Preparation
APT setup · full upgrade · admin utilities · Bash completion · Vim config · root shell customization — a consistent baseline on every box.

### 🔐 SSH Configuration
| Setting | Value |
|---|---|
| Protocol | SSH 2 only |
| Root login | `PermitRootLogin prohibit-password` |
| Custom port | **`29019`** |
| Debian banner | Disabled |
| Pre-auth banner | Enabled |
| Validation | `sshd -t` before every restart |

> ⚠️ **Heads up:** confirm the new SSH port is allowed by your firewall *before* applying this remotely — nobody wants to get locked out of a box three states away.

### 🛠️ Administrative Environment
`fzf` · `grc` · `bash-completion` · colored output · custom `ls`/network aliases · standardized prompt.

### 🔑 SSH Key Management
Drops a predefined public key into `/root/.ssh/authorized_keys` with correct permissions.

> 🔒 **Security note:** review and rotate embedded keys per your org's access-control policy.

### 🪧 Login Banners
- **Pre-auth:** `/etc/issue.net` shows an access notice before login.
- **Post-auth:** dynamic profile script prints hostname, local IP, date/time, and an access notice on every login.

---

## 🧩 Service Catalog

| Service | Technology / Purpose |
|---|---|
| 📊 Monitoring | Zabbix Agent 2 |
| 📈 SmokePing | Latency & network quality monitoring |
| 🌐 DNS Recursive | Unbound |
| 🌐 DNS Reverse | BIND9 |
| 📁 FTP | vsftpd |
| ⏰ NTP | chrony / NTP.br |
| ⚡ Speedtest | Ookla Speedtest CLI |
| 🔌 Minha Conexão | Connection monitoring & diagnostics |
| 🚦 nPerf | Throughput testing / iperf3 |
| 📝 Graylog | Centralized logging |
| 🗺️ phpIPAM | IP address management |
| 🛡️ Krill | RPKI Certificate Authority |

Modular by design — drop in a new service without touching the core engine.

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
🌐 DNS Server        📊 Monitoring Server   📝 Logging Server    🚦 Network Tools Server
└── DNS Recursive    └── Zabbix             └── Graylog          └── Speedtest
└── DNS Reverse      └── SmokePing                               └── nPerf
                                                                   └── NTP
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

## 📝 Logging

| Log | Path |
|---|---|
| Main provisioning log | `/var/log/upisp-setup.log` |
| Temporary APT log | `/tmp/upisp-apt.log` |

---

## ✅ Requirements

- Debian 12 (Bookworm)
- Root privileges
- Internet connectivity
- `apt` · `bash` · `systemd` · `dialog`

Some service modules have extra dependencies — check the script under `scripts/services/`.

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

- [ ] Debian version detection
- [ ] Installation profiles
- [ ] Non-interactive provisioning mode
- [ ] Service dependency management
- [ ] Post-installation validation
- [ ] Improved error handling
- [ ] Provisioning reports
- [ ] Configuration rollback
- [ ] Centralized service configuration
- [ ] Expanded ISP service catalog
- [ ] Improved Debian 13 support
- [ ] Modular plugin architecture

---

## 🤝 Contributing

Contributions welcome! New service modules should follow the existing modular pattern.

1. Clearly define the service's requirements
2. Keep service-specific logic isolated
3. Validate config before restarting any service
4. Provide meaningful, structured logging
5. Avoid hard-coded environment-specific values
6. Document requirements and exposed ports

---

## 🔒 Security

Runs with **root privileges** and can touch critical OS components. Always review the source before running scripts from an external location:

- SSH configuration & embedded keys
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