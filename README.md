# Setup Server

> **Server provisioning and infrastructure automation for ISP environments.**

![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-A81D33?style=flat-square\&logo=debian\&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?style=flat-square\&logo=gnu-bash\&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-333333?style=flat-square\&logo=linux\&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-2F80ED?style=flat-square)

---

## Overview

**Setup Server** is a modular Bash-based provisioning tool designed to automate the preparation, configuration, and deployment of Linux servers used in **Internet Service Provider (ISP) infrastructure**.

The project consolidates recurring operational procedures into a standardized workflow, reducing manual intervention and providing a consistent baseline across servers.

It is intended for environments where services such as DNS, monitoring, logging, network diagnostics, IP address management, NTP, and other infrastructure components need to be deployed repeatedly and predictably.

---

## Purpose

Deploying a production server involves more than installing an operating system.

A typical provisioning process may require:

* System updates
* Repository configuration
* Essential package installation
* SSH configuration
* Access control
* Administrative environment customization
* Monitoring tools
* Network diagnostics
* DNS infrastructure
* Time synchronization
* Logging
* IP address management
* RPKI infrastructure
* Performance testing services

These procedures are often repeated across multiple servers and environments.

**Setup Server exists to standardize this process.**

The objective is not to replace administrative decisions, but to automate the repetitive and well-defined parts of server provisioning.

---

## Architecture

The project follows a modular architecture where system preparation, shared functions, configuration files, and service deployment are separated into distinct components.

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

### `config/`

Contains configuration templates and system-level configuration files used during provisioning.

### `lib/`

Contains reusable Bash functions and utilities shared across provisioning modules.

### `scripts/`

Contains the primary system configuration stages.

The numbered scripts establish the execution order for fundamental server preparation tasks.

### `scripts/services/`

Contains individual service provisioning modules.

Each service is isolated into its own script, allowing the service catalog to evolve independently from the core provisioning workflow.

### `setup_server.sh`

The main interactive orchestrator.

It provides the administrator with a `dialog`-based interface for selecting the operations to be executed.

### `install.sh`

Bootstrap script responsible for initiating the Setup Server installation process.

---

## Provisioning Workflow

The general provisioning workflow can be represented as:

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

The administrator remains responsible for selecting the appropriate components for each server.

---

# Features

## System Preparation

The base system module provides common preparation tasks, including:

* APT repository configuration
* System update and upgrade
* Installation of administrative utilities
* Bash completion
* Vim configuration
* Root shell customization
* Standardized system environment

---

## SSH Configuration

The SSH module applies a predefined baseline to the OpenSSH service.

Current configuration includes:

* SSH Protocol 2
* `PermitRootLogin prohibit-password`
* Custom SSH port
* Debian SSH banner disabled
* Pre-authentication banner
* Configuration validation using `sshd -t`
* Service restart after successful validation

The current default SSH port configured by the project is:

```text
29019
```

> **Important:** When deploying remotely, ensure that the new SSH port is permitted by the network and firewall configuration before applying the change.

---

## Administrative Environment

The project provides a standardized environment for the `root` account.

This includes commonly used administrative aliases and utilities such as:

* `fzf`
* `grc`
* `bash-completion`
* Colored command output
* Customized `ls` aliases
* Network-oriented command aliases
* Standardized shell prompt

The purpose is to provide a consistent operational environment across managed servers.

---

## SSH Key Management

The provisioning workflow supports adding a predefined public SSH key to:

```text
/root/.ssh/authorized_keys
```

Appropriate permissions are applied to the SSH directory and authorized keys file.

> **Security consideration:** Public keys embedded in provisioning scripts should be reviewed and managed according to the organization's access-control policy.

---

## Login Banners

The project supports both pre-authentication and post-authentication banners.

### Pre-authentication

The `/etc/issue.net` banner provides an access notice before authentication.

### Post-authentication

A dynamic profile script displays operational information after login, including:

* Hostname
* Local IP address
* Current date and time
* Administrative access notice

This provides administrators with immediate context when connecting to infrastructure servers.

---

# Service Catalog

Setup Server is designed around the operational requirements commonly found in ISP environments.

The current service modules include:

| Service       | Technology / Purpose                   |
| ------------- | -------------------------------------- |
| Monitoring    | Zabbix Agent 2                         |
| SmokePing     | Latency and network quality monitoring |
| DNS Recursive | Unbound                                |
| DNS Reverse   | BIND9                                  |
| FTP           | vsftpd                                 |
| NTP           | chrony / NTP.br                        |
| Speedtest     | Ookla Speedtest CLI                    |
| Minha Conexão | Connection monitoring and diagnostics  |
| nPerf         | Throughput testing / iperf3            |
| Graylog       | Centralized logging                    |
| phpIPAM       | IP address management                  |
| Krill         | RPKI Certificate Authority             |

The service catalog is intentionally modular so additional infrastructure components can be incorporated without changing the overall architecture.

---

# Interactive Interface

Setup Server uses `dialog` to provide an interactive terminal interface.

The administrator can select multiple operations during the initial provisioning process.

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

Service deployment has its own selection interface, allowing the administrator to provision only the components required for a particular server.

This makes it possible to use the same provisioning tool for different roles within the infrastructure.

For example:

```text
DNS Server
    └── DNS Recursive
    └── DNS Reverse

Monitoring Server
    └── Zabbix
    └── SmokePing

Logging Server
    └── Graylog

Network Tools Server
    └── Speedtest
    └── nPerf
    └── NTP
```

---

# Logging

Execution logs are maintained during the provisioning process.

The main log file is:

```text
/var/log/upisp-setup.log
```

APT operations are temporarily recorded in:

```text
/tmp/upisp-apt.log
```

The logging mechanism is intended to facilitate troubleshooting, auditing, and operational verification after provisioning.

---

# Requirements

The project currently targets Debian-based Linux servers.

Recommended environment:

* Debian 12 (Bookworm)
* Root privileges
* Internet connectivity
* APT package manager
* Bash
* `systemd`
* `dialog`

Some service modules may have additional requirements depending on their implementation.

---

# Installation

For a clean Debian installation, execute the bootstrap command as `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Glledson/Setup_Server/main/install.sh)"
```

Alternatively, clone the repository and execute the setup manually:

```bash
git clone https://github.com/Glledson/Setup_Server.git
cd Setup_Server
chmod +x setup_server.sh
./setup_server.sh
```

---

# Operational Considerations

Setup Server performs system-level modifications.

Before deploying it to production, review the configuration of the modules being executed.

Particular attention should be given to:

* SSH access
* Firewall rules
* APT repositories
* Root SSH keys
* Network configuration
* Service ports
* Existing services
* Existing configuration files

The provisioning process should preferably be tested in a controlled environment before being applied to critical infrastructure.

---

# Design Principles

The project is guided by a few operational principles.

### Reproducibility

The same provisioning procedure should produce a consistent baseline.

### Modularity

Services should remain independent from the core system configuration.

### Transparency

System modifications should be identifiable and logged.

### Maintainability

The project should remain simple enough to be understood and maintained by infrastructure engineers.

### Operational Efficiency

Automation should eliminate repetitive tasks without hiding important administrative decisions.

---

# Roadmap

Planned improvements include:

* [ ] Debian version detection
* [ ] Installation profiles
* [ ] Non-interactive provisioning mode
* [ ] Service dependency management
* [ ] Post-installation validation
* [ ] Improved error handling
* [ ] Provisioning reports
* [ ] Configuration rollback
* [ ] Centralized service configuration
* [ ] Expanded ISP service catalog
* [ ] Improved Debian 13 support
* [ ] Modular plugin architecture

---

# Contributing

Contributions are welcome.

New service modules should follow the project's modular approach and avoid introducing unnecessary dependencies into the core provisioning engine.

When contributing a new module, consider:

1. Clearly define the service requirements.
2. Keep service-specific logic isolated.
3. Validate configurations before restarting services.
4. Provide meaningful logging.
5. Avoid hard-coded environment-specific values whenever possible.
6. Document operational requirements and exposed ports.

---

# Security

This project operates with **root privileges** and can modify critical operating system components.

Always inspect the source code before executing provisioning scripts obtained from external locations.

In particular, review:

* SSH configuration
* Embedded SSH keys
* Repository definitions
* Service configuration
* Network ports
* Privileged commands

Never deploy an unreviewed provisioning script directly to critical production infrastructure.

---

# License

This project is distributed under the **MIT License**.

See the `LICENSE` file for the complete license text.

---

<div align="center">

**Setup Server**

*Infrastructure provisioning for ISP environments.*

**Linux · Networking · Automation · Infrastructure · ISP**

</div>
