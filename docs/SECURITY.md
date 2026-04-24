# Sécurité A.S.I.P.

## Philosophie

La sécurité dans A.S.I.P. repose sur 3 principes directeurs inspirés des référentiels ANSSI (Agence Nationale de la Sécurité des Systèmes d'Information) et de la méthode ERIS/SecNumAcadémie :

1. **Shift-Left Security** — La sécurité est vérifiée dès le push, pas en production
2. **Zero Trust interne** — Chaque VLAN est isolé, chaque flux est explicitement autorisé
3. **Conformité continue** — Goss valide l'état attendu en permanence, l'IA corrige les dérives

---

## Segmentation réseau

### Couches de pare-feu

Deux couches de filtering sont appliquées simultanément :

```
┌─────────────────────────────────────────────────────────────┐
│                    COUCHE 1 : Proxmox Firewall              │
│  Security groups appliqués par NIC virtuelle (tag VLAN)     │
│  Politique par défaut : DROP ALL                            │
│  Règles : accept uniquement les flux explicites par SG     │
├─────────────────────────────────────────────────────────────┤
│                    COUCHE 2 : UFW (Host)                    │
│  Ansible hardening role sur chaque VM                       │
│  default: deny incoming, deny routed, allow outgoing        │
│  Règles par rôle (ad: 53/88/389/445/636, etc.)            │
├─────────────────────────────────────────────────────────────┤
│                    COUCHE 3 : OPNsense (Inter-VLAN)         │
│  Routage inter-VLAN avec règles de filtrage                 │
│  IDS/IPS (Suricata) sur le trafic inter-VLAN               │
│  NAT sortant via proxy Management VLAN                      │
└─────────────────────────────────────────────────────────────┘
```

### Security Groups Proxmox

| Security Group | Règles entrantes | Source |
|---------------|-----------------|--------|
| `ad-services` | TCP:53,88,135,139,389,445,464,636,3268,3269 + UDP:53,88,123,137,138,389,464 | 203.0.113.0/24 |
| `dhcp-service` | UDP:67,68 from 203.0.113.0/24, TCP+UDP:53 from 203.0.113.0/24 | Clients + internal |
| `vaultwarden-service` | TCP:443,80 from 203.0.113.0/24 | All internal |
| `collab-service` | TCP:443,444 from 203.0.113.0/24, TCP:587,993 from 203.0.113.0/24 | Clients |
| `keycloak-service` | TCP:8443 from 203.0.113.0/24 | All internal |
| `step-ca-service` | TCP:443 from 203.0.113.0/24 | All internal |
| `mgmt-access` | TCP:22 from 203.0.113.0/24, TCP:8006 from 203.0.113.0/24 | Ansible + Proxmox UI |
| `monitoring-service` | TCP:9090,3000,3100 from 203.0.113.0/24 | All internal |
| `bastion-service` | TCP:22 from 203.0.113.0/24 + out TCP:22 to 203.0.113.0/24 | SSH gateway |
| `dmz-proxy-service` | TCP:443,80,8443,444 from 203.0.113.0/24 | Reverse proxy |
| `haproxy-lb` | TCP:443,80 from 203.0.113.0/24 | Load balancing |
| `postgresql-service` | TCP:5432 from 203.0.113.0/24, TCP:8008,8009 from 203.0.113.0/24 | DB + Patroni |
| `watchdog-service` | TCP:8080 from 203.0.113.0/24, TCP:22 from 203.0.113.0/24 | Webhook + SSH |

### Politiques de trafic prohibé

| Source | Destination | Protocole | Raison |
|--------|-------------|-----------|--------|
| Clients (40) | Management (10) | ALL | Isolation stricte — clients ne touchent jamais le management |
| DMZ (50) | Management (10) | ALL | DMZ est une zone non-fiable |
| Toute VM | Internet (hors proxy) | ALL | Pas d'accès Internet direct, tout egress via proxy MGMT |
| VLAN interne | VLAN interne (même VLAN) | Non-applicatif | Pas de VM-à-VM dans même VLAN sauf nécessité |

---

## Hardening ANSSI (CIS Benchmark)

Le durcissement est assuré par **deux rôles Ansible complémentaires** :

1. **`infra-proxmox/hardening`** (BASE) — SSH, auditd, AppArmor, UFW, pwquality, CrowdSec, mount options, sysctl réseau, package removal
2. **`asip/hardening`** (COMPLÉMENT) — pam_faillock, AIDE, auditd immutable, SUID audit, SSH ANSSI, journald, banner, unattended-upgrades
3. **`asip/hardening/host-pve.yml`** (PVE HOST ONLY) — kernel.* sysctl, module blacklist, GRUB, coredumps

> **Note LXC** : Les conteneurs LXC partagent le noyau du host Proxmox. Les paramètres `kernel.*`, `fs.protected_*` et les blacklists de modules ne peuvent être configurés que sur le PVE host via `--tags host-hardening --limit pve`.

### Kernel (sysctl) — Conteneurs LXC (namespaced)

```
# Réseau (infra-proxmox base)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Mémoire (infra-proxmox base)
fs.suid_dumpable = 0                     # Pas de core dumps SUID

# Réseau durci (ASIP complément)
net.ipv4.conf.all.secure_redirects = 0   # ANSSI — pas de redirects sécurisés
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.tcp_timestamps = 0              # ANSSI — timestamps TCP off
net.ipv4.conf.all.bootp_relay = 0
net.ipv4.conf.default.bootp_relay = 0
net.ipv4.conf.all.proxy_arp = 0
net.ipv4.conf.default.proxy_arp = 0
```

### Kernel (sysctl) — PVE Host uniquement

```
# Ces paramètres ne sont PAS namespaced dans LXC
# Ils doivent être configurés sur le Proxmox VE host
kernel.randomize_va_space = 2           # ASLR complet
kernel.dmesg_restrict = 1               # Restriction dmesq
kernel.kptr_restrict = 2                # Restriction pointeurs noyau
fs.protected_hardlinks = 1              # Protection liens durs
fs.protected_symlinks = 1               # Protection liens symboliques
fs.protected_fifos = 2                  # Protection fifos
fs.protected_regular = 2                # Protection fichiers regular
dev.tty.ldisc_autoload = 0              # Désactive autoload TTY
```

### SSH

| Paramètre | Valeur | Rôle | Norme |
|-----------|--------|------|-------|
| `Port` | 22 (ou custom) | Base | Non-standard en option |
| `PermitRootLogin` | `no` | Base | ANSSI |
| `PasswordAuthentication` | `no` | Base | ANSSI — clés ed25519 uniquement |
| `PermitEmptyPasswords` | `no` | Base | ANSSI |
| `MaxAuthTries` | 3 | Base | ANSSI — anti brute-force |
| `MaxSessions` | 3 | Base | ANSSI |
| `X11Forwarding` | `no` | Base | ANSSI |
| `ClientAliveInterval` | 300 | Base | ANSSI |
| `ClientAliveCountMax` | 2 | Base | ANSSI |
| `Ciphers` | chacha20,aes256-gcm | Base | ANSSI |
| `MACs` | hmac-sha2-512,hmac-sha2-256 | Base | ANSSI |
| `KexAlgorithms` | curve25519-sha256 | Base | ANSSI |
| `TrustedUserCAKeys` | SSH CA step-ca | Base | PKI interne |
| `HostbasedAuthentication` | `no` | **ASIP** | ANSSI GCR |
| `IgnoreRhosts` | `yes` | **ASIP** | ANSSI GCR |
| `PermitUserEnvironment` | `no` | **ASIP** | ANSSI GCR |
| `MaxStartups` | `10:30:60` | **ASIP** | CIS 5.2.14 |
| `StrictModes` | `yes` | **ASIP** | CIS 5.2.13 |

### Authentification

| Contrôle | Valeur | Rôle | Norme |
|----------|--------|------|-------|
| `PASS_MAX_DAYS` | 90 | Base | ANSSI — rotation |
| `PASS_MIN_DAYS` | 7 | Base | ANSSI |
| `PASS_WARN_AGE` | 14 | Base | ANSSI |
| `ENCRYPT_METHOD` | SHA512 | Base | ANSSI |
| `minlen` (pwquality) | 14 | Base | ANSSI |
| `minclass` (pwquality) | 4 | Base | ANSSI |
| `dcredit/ucredit/lcredit/ocredit` | -1 | Base | ANSSI |
| `maxrepeat` | 3 | Base | ANSSI |
| `pam_faillock` deny | 5 | **ASIP** | CIS 5.2.2 — lockout après 5 échecs |
| `pam_faillock` unlock_time | 900s | **ASIP** | CIS 5.2.2 |
| `pam_faillock` even_deny_root | true | **ASIP** | CIS 5.2.2 |
| `pam_pwhistory` remember | 5 | **ASIP** | CIS 5.3.3 — anti-reuse |

### SUID/SGID (ASIP)

Les binaires SUID suivants sont dépouillés de leur bit SUID :

| Binaire | Raison |
|---------|--------|
| `/usr/bin/chsh` | Pas de changement shell via SUID |
| `/usr/bin/chfn` | Pas de changement finger via SUID |
| `/usr/bin/newgrp` | Pas de changement groupe via SUID |
| `/usr/bin/gpasswd` | Pas de gestion groupe via SUID |
| `/usr/bin/mount` | Pas de montage utilisateur |
| `/usr/bin/umount` | Pas de démontage utilisateur |
| `/usr/bin/passwd` | Géré via PAM, bit SUID retiré si policy locale |
| `/usr/bin/su` | Accès via sudo uniquement |
| `/usr/bin/pkexec` | PolicyKit exploit (CVE historiques) |
| `/usr/lib/openssh/ssh-keysign` | Pas besoin SUID avec certificats |

### Filesystem

| Montage | Options | Rôle | Raison |
|---------|---------|------|--------|
| `/tmp` | `rw,nosuid,nodev,noexec,mode=1777,size=2G` | Base | tmpfs, pas d'exécution |
| `/var/tmp` | `rw,nosuid,nodev,noexec` | Base | Pas d'exécution |
| `/home` | `rw,nosuid,nodev` | Base | Pas de SUID dans les homes |

### Audit et logging

| Outil | Configuration | Rôle | Usage |
|-------|---------------|------|-------|
| `auditd` | Règles CIS (login, mount, sudo, /etc/passwd, /etc/shadow, réseau) | Base | Traçabilité complète |
| `auditd` | Flag `-e 2` (immutable) | **ASIP** | Règles non modifiables sans reboot |
| `rsyslog` | Forward central vers ad-server | Base | Centralisation des logs |
| `logrotate` | Rotation 30 jours | Base | Prévention saturation |
| `AIDE` | Baseline post-deploy, check quotidien (4h00) | **ASIP** | Détection modification fichiers |
| `AppArmor` | Enforce mode, profils par service | Base | Confinement processus |
| `journald` | Storage=persistent, SystemMaxUse=500M | **ASIP** | Logs persistants + taille limitée |

### Login banner

Le rôle ASIP déploie un avertissement légal dans `/etc/issue` et `/etc/issue.net` conforme aux exigences ANSSI/CIS.

### Mises à jour automatiques

`unattended-upgrades` est configuré pour appliquer uniquement les mises à jour de sécurité (`${distro_id}:${distro_codename}-security`), sans reboot automatique.

### Module blacklist (PVE host)

Les modules suivants sont bloqués sur le Proxmox VE host :

| Module | Raison | Norme |
|--------|--------|-------|
| `usb-storage` | Pas de stockage USB | CIS 3.5 |
| `dccp` | Protocole réseau rare | CIS 3.5 |
| `sctp` | Protocole réseau rare | CIS 3.5 |
| `rds` | Protocole réseau rare | CIS 3.5 |
| `tipc` | Protocole réseau rare | CIS 3.5 |

---

## Détection et réponse aux incidents

### CrowdSec

Installé sur toutes les VMs, CrowdSec fournit une détection collaborative :

| Composant | Configuration |
|-----------|---------------|
| `crowdsec` (engine) | Collections : ssh, nginx, apache, linux, postfix |
| `crowdsec-firewall-bouncer` | Bannissement automatique via nftables |
| Décisions locales | Ban 2h après 5 failures SSH |
| Community blocklist | Sources malveillantes connues |

### AppArmor — Profils par service

| Service | Profil | Mode |
|---------|--------|------|
| Samba4 (smbd/nmbd) | `usr.sbin.smbd` | Enforce |
| Nginx | `usr.sbin.nginx` | Enforce |
| Dovecot | `usr.lib.dovecot.*` | Enforce |
| Postfix | `usr.sbin.master` | Enforce |
| Kea DHCP | `usr.sbin.kea-dhcp4` | Enforce |

---

## Stratégie TLS/PKI

### Infrastructure de certificats

```
┌──────────────────────────────────┐
│  Smallstep step-ca               │
│  203.0.113.21                     │
│  Root CA: offline (air-gapped)   │
│  Intermediate: step-ca online    │
│  ACME: auto-enrollment           │
│  SSH CA: certificates SSH        │
└─────────┬────────────────────────┘
          │
    ┌─────┴──────┐
    │  ACME auto │
    │  -enroll   │
    └─────┬──────┘
          │
   ┌──────┴──────────────────────────────┐
   │  Certificats délivrés automatiquement │
   │  • nextcloud.corp.local              │
   │  • onlyoffice.corp.local             │
   │  • vault.corp.local                  │
   │  • keycloak.corp.local               │
   │  • mail-server.corp.local            │
   │  • ad-server.corp.local              │
   │  • mcp-watchdog.corp.local           │
   │  Durée: 90 jours, renouvel à 30j    │
   └──────────────────────────────────────┘
```

### Certificats SSH

- step-ca génère des certificats SSH signés par la CA
- Chaque hôte fait confiance à la CA SSH dans `TrustedUserCAKeys`
- Les utilisateurs s'authentifient via `step ssh login <user>` (SSO Keycloak)
- Durée de validité : 8h, renouvelable

---

## Shift-Left Security (CI/CD)

### Pipeline Forgejo Actions

Le pipeline de sécurité est intégré directement dans le workflow CI/CD de Forgejo. Chaque push déclenche automatiquement les contrôles de sécurité.

```
  git push ──► Forgejo :3000
                  │
                  ▼
        ┌─────────────────┐
        │ security-scan.yml │  (trigger: push + schedule daily)
        │                   │
        │ 1. Trivy fs scan  │  ← Scan du code + configs
        │    CRITICAL/HIGH  │
        │ 2. Trivy image    │  ← Scan des conteneurs déployés
        │    vaultwarden    │
        │    keycloak       │
        │    postgres       │
        │    nginx          │
        │ 3. Fail si trouvée│  ← Bloque le merge
        └─────────┬─────────┘
                  │
        ┌─────────▼─────────┐
        │  terraform-deploy │
        │  terraform plan   │  ← Obligatoire avant apply
        │  (dry-run)        │
        └─────────┬─────────┘
                  │
        ┌─────────▼─────────┐
        │  ansible-deploy   │
        │  --syntax-check   │  ← Validation syntaxique
        │  --check --diff   │  ← Dry-run avec diff
        └─────────┬─────────┘
                  │
           Déploiement OK
```

### Seuils de criticité Trivy

| Sévérité | Action |
|-----------|--------|
| CRITICAL | Bloque le pipeline — merge interdit |
| HIGH | Alerte + rapport, merge avec approbation |
| MEDIUM | Rapport informatif |
| LOW/UNKNOWN | Ignoré |

### Conformité continue (Goss)

Le rôle `goss-poll` déploie sur chaque VM :

- Un fichier `/etc/goss/goss.yaml` décrivant l'état attendu
- Un timer systemd `goss-poll.timer` (toutes les 5 minutes)
- Un service `goss-poll.service` qui exécute la validation
- Un webhook vers `http://203.0.113.50:8080/webhook/goss` en cas de drift

**Exemple de vérifications Goss :**

```yaml
# /etc/goss/goss.yaml (extraits)
service:
  sshd:
    running: true
    enabled: true
  ufw:
    running: true
    enabled: true
  crowdsec:
    running: true
    enabled: true
  auditd:
    running: true
    enabled: true
  goss-poll:
    running: true
    enabled: true

file:
  /etc/ssh/sshd_config:
    exists: true
    contains:
      - "!/PermitRootLogin yes/"
      - "!/PasswordAuthentication yes/"
      - "/PermitEmptyPasswords no/"
  /etc/goss/goss.yaml:
    exists: true
  /etc/ufw/ufw.conf:
    exists: true

package:
  apparmor:
    installed: true
  auditd:
    installed: true
  ufw:
    installed: true
  goss:
    installed: true

command:
  ufw status:
    exit-status: 0
    stdout:
      - "/Status: active/"
  aa-status --enabled:
    exit-status: 0
  goss -g /etc/goss/goss.yaml validate:
    exit-status: 0
```

---

## Gestion des secrets

| Secret | Stockage | Rotation | Méthode |
|--------|---------|----------|---------|
| Samba4 AD admin password | ansible-vault | Trimestrielle | `samba-tool user setpassword` |
| Nextcloud DB password | ansible-vault | Trimestrielle | `occ config:system:set` |
| Vaultwarden admin token | ansible-vault | Trimestrielle | Variable d'environnement |
| Kea HMAC key | ansible-vault | Trimestrielle | Config Kea |
| SSH host keys | Renouvelés par hardening role | Annuelle | Ansible |
| Smallstep CA root key | HSM / air-gapped | Jamais | Stockage physique |
| TLS certificates | step-ca ACME | 90 jours (auto) | Smallstep |
| Proxmox API token | Proxmox UI + tfvars | Semestrielle | Régénération manuelle |
| Forgejo runner token | Forgejo UI | Annuelle | `forgejo runner register` (sur PC hôte) |
| LocalStack mock keys | Hardcodés `test/test` | N/A | Pas de secrets réels (mock) |

### ansible-vault

Les secrets sont chiffrés dans `group_vars/all/vault.yml` :

```bash
# Visualiser
ansible-vault view group_vars/all/vault.yml --vault-password-file ~/.vault_pass

# Éditer
ansible-vault edit group_vars/all/vault.yml --vault-password-file ~/.vault_pass

# Re-key (changer le mot de passe)
ansible-vault rekey group_vars/all/vault.yml
```

---

## Sauvegarde (Stratégie 3-2-1)

| Copie | Média | Fréquence | Rétention |
|-------|-------|-----------|-----------|
| 1 — Primaire | Proxmox local-lvm (SSD) | Live | — |
| 2 — Locale | NAS NFS (HDD) | Quotidienne | 30 jours |
| 3 — Offsite (mock) | LocalStack S3 `asip-backup` | Quotidienne | 30 jours |

### Procédures de restauration

```bash
# Samba4 AD
sudo samba-tool domain backup restore --targetdir=/var/lib/samba --backup-file=<backup>

# Nextcloud
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
# Restaurer DB + data
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off

# Depuis LocalStack
aws --endpoint-url=http://localhost:4566 s3 cp s3://asip-backup/<path> /restore/<path>
```

---

## Réponse aux incidents

### Niveaux de sévérité

| Niveau | Description | Exemples | SLA réponse |
|--------|------------|----------|-------------|
| **P1 — Critique** | Panne service affectant tous les utilisateurs | AD DC down, réseau coupe | 15 min |
| **P2 — Élevé** | Panne partielle ou faille sécurité | Vaultwarden compromis, cert expiré | 1h |
| **P3 — Moyen** | Dégradation, échec non-critique | DHCP épuisé, disque plein | 4h |
| **P4 — Faible** | Informatif, cosmétique | Anomalies log, cron échoué | J+1 |

### Auto-remédiation vs Escalade

| Incident | Détection | Auto-remédiation | Escalade si échec |
|----------|-----------|------------------|-------------------|
| Config SSH modifiée | Goss drift | Ansible `hardening` role | P2 — notification ingénieur |
| Service down | Goss process check | `systemctl restart <service>` | P1 — alerte + intervention |
| Faille CRITICAL container | Trivy scan | Pas d'auto-fix (risque breaking) | P2 — bloque déploiement, alerte |
| AIDE integrity violation | AIDE daily check | Pas d'auto-fix (investigation) | P1 — investigation manuelle |
| Drift Goss mineur (< 3 checks) | Poller 5 min | `ansible-playbook --tags <role>` | Log, notification |