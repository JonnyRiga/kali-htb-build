# custom-kali-build

Ansible playbook that provisions a fresh Kali Linux VM into a fully-loaded pentest workstation. Inspired by [IppSec's parrot-build](https://github.com/IppSec/parrot-build), rebuilt from the ground up for **Kali Linux Rolling** (XFCE / zsh).

## How This Differs from IppSec's parrot-build

[IppSec's parrot-build](https://github.com/IppSec/parrot-build) is the original inspiration and well worth studying. This repo takes the same concept and rebuilds it with a different target and scope:

| | IppSec's parrot-build | This repo |
|---|---|---|
| **Target OS** | Parrot HTB Edition | Kali Linux Rolling (XFCE / zsh) |
| **Setup** | Manual 6-step process | Single `./bootstrap.sh` command |
| **Ansible install** | Manual (`pip install ansible`) | Auto-handled by bootstrap |
| **Tool isolation** | Global installs | pipx virtualenvs for impacket, netexec, certipy-ad, bloodhound.py |
| **BloodHound** | Legacy version | BloodHound CE via Docker Compose (auto-started, password saved) |
| **Binary tools** | Compiled from source or manual | Pre-built binaries for kerbrute, chisel, ligolo-ng |
| **Logging** | Not included | ufw (SYN logging) + auditd + laurel structured audit logs |
| **Idempotent** | Not designed for re-runs | Fully idempotent — safe to re-run at any time |
| **Selective runs** | All-or-nothing | Tag-based — run individual roles without touching the rest |
| **Known issues doc** | Minimal | Explicit workarounds table for every tool with install problems |

If you're on Parrot, use IppSec's. If you're on Kali and want a one-command fully automated build, use this.

## What It Does

- Installs and configures **50+ pentest tools** across recon, exploitation, AD attacks, C2/tunnelling, reversing, and more
- Replaces Kali's stock package versions of key tools (impacket, netexec, certipy-ad, bloodhound.py) with **pipx-isolated latest-from-git** builds to avoid dependency hell
- Downloads pre-built binaries for tools that break when compiled from source (kerbrute, chisel, ligolo-ng)
- Sets up **BloodHound CE** via Docker Compose — auto-starts and captures the initial admin password
- Configures **ufw** with SYN logging, **auditd** with [laurel](https://github.com/threathunters-io/laurel) for structured audit logs
- Deploys **Firefox extension policies** (DarkReader, FoxyProxy, Wappalyzer) and Burp Suite extras (JRuby/Jython JARs)
- Installs official **Docker CE** from Docker's repository (replaces the Kali `docker.io` package)
- Drops PEASS-ng, SharpCollection, Chainsaw, and SecLists into `/opt/`
- Installs **VS Code** from Microsoft's official apt repo with pentest/dev extensions pre-installed
- Deploys custom personal tools (`privy.sh`, `sthunt.sh`) to `/usr/local/bin` with shell aliases
- Configures tmux, custom zsh prompt (VPN/IP-aware), zsh aliases, GOPATH, and NOPASSWD sudo
- Fully **idempotent** — safe to re-run at any time

## Quick Start

```bash
git clone https://github.com/JonnyRiga/custom-kali-build.git
cd custom-kali-build
./bootstrap.sh
```

That's it. `bootstrap.sh` handles everything:
1. Installs `pipx` if missing
2. Installs Ansible via `pipx`
3. Installs Galaxy collection dependencies
4. Runs the full playbook (prompts for sudo password)

### Manual Run (if Ansible is already installed)

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml -K
```

## Tags

Every role has its own tag so you can run individual sections:

```bash
# Full build
ansible-playbook site.yml -K

# Just AD attack tools
ansible-playbook site.yml --tags ad_attacks -K

# Multiple tags
ansible-playbook site.yml --tags "recon,c2_tunnelling" -K

# Dry-run
ansible-playbook site.yml --tags ad_attacks --check -K
```

Or via `bootstrap.sh`:

```bash
./bootstrap.sh --tags recon
./bootstrap.sh --tags "ad_attacks,c2_tunnelling"
```

| Tag | Tools / Actions |
|-----|-----------------|
| `base` | GitHub CLI (gh), Go, pipx, jq, flameshot, exiftool, git, wget, curl, vim, neovim, tmux, zsh, 7zip, rsyslog, core packages |
| `docker` | Official Docker CE (removes `docker.io`), adds user to docker group |
| `recon` | nmap, ffuf, feroxbuster, gobuster, wfuzz, enum4linux, enum4linux-ng, smbmap, dnsrecon, dnsenum, whatweb, wafw00f, nikto, masscan, python3-ldapdomaindump |
| `exploitation` | metasploit, sqlmap, hydra, medusa, john, hashcat, responder, exploitdb/searchsploit |
| `ad_attacks` | impacket (pipx), netexec (pipx), certipy-ad (pipx), bloodhound-ce (pipx+docker), kerbrute (binary), evil-winrm (gem), coercer |
| `c2_tunnelling` | chisel (linux+windows), ligolo-ng (proxy+agent linux/windows), PEASS-ng, pwncat-cs, SharpCollection |
| `reversing` | gdb, pwndbg, ghidra, radare2, binwalk, foremost, chainsaw, steghide, stegseek, ltrace, strace |
| `wordlists` | SecLists (git clone, latest), rockyou decompression, `/opt/SecLists` symlink |
| `shell_config` | tmux config (vi-mode, mouse, pane management), zsh aliases, custom zsh prompt (VPN/tun0-aware, colour-coded IP) |
| `logging` | ufw (SYN logging), auditd + laurel, rsyslog |
| `browser` | Firefox policies (DarkReader, FoxyProxy, Wappalyzer), Burp JRuby/Jython JARs |
| `burp_cert` | Download Burp CA cert (requires Burp running on `:8080`) — opt-in only |
| `system` | NOPASSWD sudo, full `apt upgrade` |
| `ide` | VS Code from Microsoft apt repo + extensions: Python, GitHub Copilot, Snyk, Hex Editor, Code Spell Checker, Solidity Auditor |
| `custom_tools` | Deploy `privy.sh` (privesc enumeration) and `sthunt.sh` (stego/web hunter) to `/usr/local/bin` with zsh aliases |

## Known Issues & Workarounds

These tools have well-documented installation problems. Each one is handled explicitly in the playbook with inline comments explaining the fix:

| Tool | Problem | This Playbook's Fix |
|------|---------|---------------------|
| **Kerbrute** | `go install` fails — Go module path changed upstream | Downloads pre-built binary from GitHub Releases |
| **CrackMapExec** | Abandoned project, dependency conflicts | Not installed. Uses **NetExec** (maintained fork) via pipx from git |
| **NetExec (apt)** | Kali apt version lags behind, conflicts with pipx | Removes apt package, installs latest from git via pipx |
| **Certipy-ad** | Global pip install conflicts with impacket | Installed via pipx (isolated virtualenv) |
| **Evil-WinRM (apt)** | Broken Ruby dependencies on current Kali | Installed via `gem install` with full dependency chain |
| **BloodHound.py** | Kali apt has legacy version, not CE-compatible | CE branch installed via pipx from git |
| **SecLists (apt)** | apt-installed `/usr/share/seclists` has no `.git` dir, blocks clone | Detects non-git directory, removes it, then clones latest from git |

## Post-Run Steps

1. **Log out and back in** — required for docker group membership and GOPATH changes
2. **Burp CA cert** — start Burp Suite, then run: `ansible-playbook site.yml --tags burp_cert -K`
3. **Ligolo-ng TUN interface** — add on first use: `sudo ip tuntap add user $USER mode tun ligolo`
4. **BloodHound CE credentials** — saved automatically to `/opt/bloodhound/server/initial-password.txt`

## File Structure

```
custom-kali-build/
├── bootstrap.sh                # One-command setup for fresh VMs
├── site.yml                    # Main playbook entry point
├── requirements.yml            # Ansible Galaxy collection dependencies
├── group_vars/
│   └── all.yml                 # Global variables (paths, versions, ports)
└── roles/
    ├── base/tasks/             # Core packages, Go, pipx, GitHub CLI
    ├── docker/tasks/           # Official Docker CE
    ├── recon/tasks/            # Network scanning & enumeration
    ├── exploitation/tasks/     # Exploit frameworks & credential tools
    ├── ad_attacks/tasks/       # Active Directory attack toolchain
    ├── c2_tunnelling/          # C2, tunnelling, post-exploitation
    │   └── tasks/
    ├── reversing/tasks/        # Binary analysis & debugging
    ├── wordlists/tasks/        # Wordlist management
    ├── shell_config/           # Terminal configuration
    │   ├── tasks/
    │   └── files/.tmux.conf
    ├── logging/                # Firewall & audit logging
    │   ├── tasks/
    │   ├── handlers/
    │   └── files/laurel/
    ├── browser/                # Browser & Burp Suite config
    │   ├── tasks/
    │   └── templates/
    ├── system/tasks/           # System-level configuration
    ├── ide/tasks/              # VS Code + extensions
    ├── custom_tools/           # Personal scripts (privy.sh, sthunt.sh)
    │   ├── tasks/
    │   └── files/
    └── terminal/               # QTerminal config (not wired into site.yml)
        ├── tasks/
        └── files/
```

## Tested On

- Kali Linux 2025.4 Rolling (kernel 6.18.12)
- XFCE desktop / zsh shell
- VMware Workstation (open-vm-tools)
- Ansible 2.20.x via pipx

## Credits

- [IppSec](https://github.com/IppSec/parrot-build) — original parrot-build concept and `githubdownload.py` design
- [BloodHound CE](https://github.com/SpecterOps/BloodHound) — SpecterOps
- [Laurel](https://github.com/threathunters-io/laurel) — threathunters.io
