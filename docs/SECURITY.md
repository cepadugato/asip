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
| `ad-services` | TCP:53,88,135,139,389,445,464,636,3268,3269 + UDP:53,88,123,137,138,389,464 | 10.10.0.0/16 |
| `dhcp-service` | UDP:67,68 from 10.10.40.0/24, TCP+UDP:53 from 10.10.0.0/16 | Clients + internal |
| `vaultwarden-service` | TCP:443,80 from 10.10.0.0/16 | All internal |
| `collab-service` | TCP:443,444 from 10.10.40.0/24, TCP:587,993 from 10.10.40.0/24 | Clients |
| `keycloak-service` | TCP:8443 from 10.10.0.0/16 | All internal |
| `step-ca-service` | TCP:443 from 10.10.0.0/16 | All internal |
| `mgmt-access` | TCP:22 from 10.10.20.0/24, TCP:8006 from 10.10.10.0/24 | Ansible + Proxmox UI |
| `monitoring-service` | TCP:9090,3000,3100 from 10.10.0.0/16 | All internal |
| `bastion-service` | TCP:22 from 10.10.0.0/16 + out TCP:22 to 10.10.0.0/16 | SSH gateway |
| `dmz-proxy-service` | TCP:443,80,8443,444 from 10.10.0.0/16 | Reverse proxy |
| `haproxy-lb` | TCP:443,80 from 10.10.0.0/16 | Load balancing |
| `postgresql-service` | TCP:5432 from 10.10.10+20.0/0, TCP:8008,8009 from 10.10.10.0/24 | DB + Patroni |
| `watchdog-service` | TCP:8080 from 10.10.0.0/16, TCP:22 from 10.10.20.0/24 | Webhook + SSH |

### Politiques de trafic prohibé

| Source | Destination | Protocole | Raison |
|--------|-------------|-----------|--------|
| Clients (40) | Management (10) | ALL | Isolation stricte — clients ne touchent jamais le management |
| DMZ (50) | Management (10) | ALL | DMZ est une zone non-fiable |
| Toute VM | Internet (hors proxy) | ALL | Pas d'accès Internet direct, tout egress via proxy MGMT |
| VLAN interne | VLAN interne (même VLAN) | Non-applicatif | Pas de VM-à-VM dans même VLAN sauf nécessité |

---

## Hardening ANSSI (CIS Benchmark)

Le rôle Ansible `hardening` applique les contrôles suivants à toutes les VMs :

### Kernel (sysctl)

```
# Réseau
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

# Mémoire
kernel.randomize_va_space = 2           # ASLR complet
fs.suid_dumpable = 0                     # Pas de core dumps SUID

# Réseau durci
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
```

### SSH

| Paramètre | Valeur | Raison |
|-----------|--------|--------|
| `Port` | 22 (ou custom) | Non-standard en option |
| `PermitRootLogin` | `no` | Pas de login root direct |
| `PasswordAuthentication` | `no` | Clés ed25519 uniquement |
| `PermitEmptyPasswords` | `no` | Pas de mots de passe vides |
| `MaxAuthTries` | 3 | Anti brute-force |
| `MaxSessions` | 3 | Limite les sessions simultanées |
| `X11Forwarding` | `no` | Pas de forwarding X11 |
| `ClientAliveInterval` | 300 | Détection sessions inactives |
| `ClientAliveCountMax` | 2 | Timeout après 10 min d'inactivité |
| `Ciphers` | chacha20,aes256-gcm | Seuls les chiffrements modernes |
| `MACs` | hmac-sha2-512,hmac-sha2-256 | Codes d'authentification forts |
| `KexAlgorithms` | curve25519-sha256,nistp384 | Échange de clés robuste |
| `TrustedUserCAKeys` | SSH CA step-ca | Certificats SSH via PKI interne |

### Authentification

| Contrôle | Valeur | Norme |
|----------|--------|-------|
| `PASS_MAX_DAYS` | 90 | ANSSI — rotation mots de passe |
| `PASS_MIN_DAYS` | 7 | ANSSI — pas de changement immédiat |
| `PASS_WARN_AGE` | 14 | ANSSI — préavis d'expiration |
| `ENCRYPT_METHOD` | SHA512 | ANSSI — hachage robuste |
| `minlen` (pwquality) | 14 | ANSSI — longueur minimum |
| `minclass` (pwquality) | 4 | ANSSI — 4 classes de caractères |
| `dcredit/ucredit/lcredit/ocredit` | -1 chacune | Au moins 1 de chaque type |
| `maxrepeat` | 3 | Pas plus de 3 caractères identiques consécutifs |
| `faillock` | 5 tentatives → verrouillage 900s | Anti brute-force PAM |

### Filesystem

| Montage | Options | Raison |
|---------|---------|--------|
| `/tmp` | `rw,nosuid,nodev,noexec,mode=1777,size=2G` | tmpfs, pas d'exécution |
| `/var/tmp` | `rw,nosuid,nodev,noexec` | Pas d'exécution |
| `/home` | `rw,nosuid,nodev` | Pas de SUID dans les homes |
| `/var/log` | `rw,nosuid,nodev,noexec` | Logs non-exécutables |

### Audit et logging

| Outil | Configuration | Usage |
|-------|---------------|-------|
| `auditd` | Règles CIS (login, mount, sudo, /etc/passwd, /etc/shadow, réseau) | Traçabilité complète |
| `rsyslog` | Forward central vers ad-server | Centralisation des logs |
| `logrotate` | Rotation 30 jours | Prévention saturation disque |
| `AIDE` | Baseline post-deploy, check quotidien | Détection de modification de fichiers |
| `AppArmor` | Enforce mode, profils par service | Confinement des processus |

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
│  10.10.20.21                     │
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

Le rôle `goss-drift` déploie sur chaque VM :

- Un fichier `/etc/goss/goss.yaml` décrivant l'état attendu
- Un timer systemd `goss-drift.timer` (toutes les 5 minutes)
- Un service `goss-drift.service` qui exécute la validation
- Un webhook vers `http://10.10.10.50:8080/webhook/goss` en cas de drift

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

file:
  /etc/ssh/sshd_config:
    exists: true
    contains:
      - "!/PermitRootLogin yes/"
      - "!/PasswordAuthentication yes/"
      - "/PermitEmptyPasswords no/"

package:
  apparmor:
    installed: true
  auditd:
    installed: true
  ufw:
    installed: true

command:
  ufw status:
    exit-status: 0
    stdout:
      - "/Status: active/"
  aa-status --enabled:
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
| Forgejo runner token | Forgejo UI | Annuelle | `forgejo runner register` |
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
awslocal s3 cp s3://asip-backup/<path> /restore/<path> --endpoint-url=http://localhost:4566
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