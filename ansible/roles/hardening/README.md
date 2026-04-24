# ASIP Hardening Role — ANSSI/CIS L1 Compliance

## Architecture

Ce rôle **complète** le rôle `infra-proxmox/ansible/roles/hardening/` existant. Il ne le remplace pas.

```
┌───────────────────────────────────────────────────────────┐
│  infra-proxmox/hardening (BASE)                           │
│  ✅ SSH ciphers/MACs/Kex, PermitRootLogin, MaxAuthTries   │
│  ✅ sysctl réseau (redirects, martians, rp_filter)       │
│  ✅ auditd rules (CIS)                                    │
│  ✅ AppArmor, UFW, pwquality, CrowdSec                     │
│  ✅ Filesystem mount options, unused FS blacklist         │
│  ✅ Package removal, umask, cron/at restrictions          │
├───────────────────────────────────────────────────────────┤
│  asip/hardening (COMPLÉMENT)                              │
│  ✅ pam_faillock (account lockout: 5 fails → 900s)        │
│  ✅ pam_pwhistory (password reuse: remember=5)            │
│  ✅ AIDE (file integrity monitoring + daily cron)          │
│  ✅ Auditd immutable flag (-e 2)                          │
│  ✅ SSH: HostbasedAuthentication, IgnoreRhosts,            │
│     PermitUserEnvironment, MaxStartups, StrictModes       │
│  ✅ SUID/SGID removal (chsh, mount, pkexec, etc.)         │
│  ✅ sysctl container-applicable (secure_redirects, etc.)  │
│  ✅ Login banner /etc/issue                               │
│  ✅ journald configuration (persistent, size limit)      │
│  ✅ World-writable files audit                            │
│  ✅ Unattended-upgrades (security only)                   │
│  ✅ Root UID 0 duplicate check                           │
├───────────────────────────────────────────────────────────┤
│  asip/hardening tasks/host-pve.yml (PVE HOST ONLY)        │
│  ✅ kernel.randomize_va_space=2 (ASLR)                    │
│  ✅ kernel.dmesg_restrict=1                                │
│  ✅ kernel.kptr_restrict=2                                │
│  ✅ fs.protected_hardlinks/symlinks/fifos/regular          │
│  ✅ Kernel module blacklist (usb-storage, dccp, sctp)     │
│  ✅ GRUB boot parameters                                 │
│  ✅ Core dump limits                                     │
└───────────────────────────────────────────────────────────┘
```

## LXC Container Support

Les conteneurs LXC partagent le noyau du host Proxmox. Certains paramètres sysctl **ne peuvent pas** être modifiés depuis l'intérieur d'un conteneur (non-namespaced) :

| Paramètre | Namespaced? | Où configurer |
|-----------|-------------|---------------|
| `kernel.randomize_va_space` | ❌ Non | PVE host (`host-pve.yml`) |
| `kernel.dmesg_restrict` | ❌ Non | PVE host (`host-pve.yml`) |
| `kernel.kptr_restrict` | ❌ Non | PVE host (`host-pve.yml`) |
| `fs.protected_*` | ❌ Non | PVE host (`host-pve.yml`) |
| `net.ipv4.conf.*.secure_redirects` | ✅ Oui | Container (`main.yml`) |
| `net.ipv4.tcp_timestamps` | ✅ Oui | Container (`main.yml`) |
| `net.ipv4.tcp_syncookies` | ❌ Non* | PVE host (host-level) |
| Module blacklists | ❌ Non | PVE host (`host-pve.yml`) |
| GRUB config | ❌ Non | PVE host (`host-pve.yml`) |

\* `tcp_syncookies` est namespaced en théorie mais PVE override en pratique.

## Usage

```bash
# Durcir tous les conteneurs (hardening base + ASIP)
ansible-playbook site.yml --tags hardening

# Durcir le host PVE uniquement
ansible-playbook site.yml --tags host-hardening --limit pve

# Durcir un conteneur spécifique
ansible-playbook site.yml --tags hardening-asip --limit mcp-watchdog
```

## Référentiels

- **ANSSI GCR** — Guide de Configuration Renforcée (2021)
- **CIS Benchmark Ubuntu 22.04** — Level 1 + Level 2
- **ERIS/SecNumAcadémie** — Méthode de durcissement