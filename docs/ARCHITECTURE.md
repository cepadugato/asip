# Architecture A.S.I.P.

## Vue d'ensemble

A.S.I.P. étend l'infrastructure Proxmox existante (19 VMs + 1 LXC + 2 routeurs OPNsense) avec un agent de surveillance IA et une simulation de cloud hybride. L'architecture repose sur 3 zones : le cluster Proxmox (on-premise), le PC hôte (Forgejo + LocalStack + Runner), et le canal MCP entre les deux.

---

## Composants d'infrastructure

### Matrice des VMs

| VM | VLAN | IP | CPU | RAM | Disk | VMID | Rôle |
|----|------|----|-----|-----|------|------|------|
| **opnsense-router** | WAN + 10-50 | 203.0.113.1 | 2 | 2G | 16G | 99 | Firewall/routeur primaire (CARP) |
| **opnsense-router-2** | WAN + 10-50 | 203.0.113.2 | 2 | 2G | 16G | 98 | Firewall/routeur backup (CARP) |
| **bastion** | 10 | 203.0.113.5 | 1 | 1G | 16G | 100 | SSH bastion + step-ca CA |
| **monitoring-server** | 10 | 203.0.113.20 | 2 | 4G | 64G | 101 | Prometheus, Grafana, Loki |
| **mcp-watchdog** | — | 203.0.113.50 | 2 | 4G | 32G | 119 | Agent IA de surveillance + auto-remédiation (LXC Ubuntu 22.04, pas VM QEMU) |
| **pg-node-1** | 10 | 203.0.113.30 | 2 | 4G | 64G | 102 | PostgreSQL Patroni nœud 1 |
| **pg-node-2** | 10 | 203.0.113.31 | 2 | 4G | 64G | 103 | PostgreSQL Patroni nœud 2 |
| **pg-node-3** | 10 | 203.0.113.32 | 2 | 4G | 64G | 104 | PostgreSQL Patroni nœud 3 |
| **ad-server** | 20 | 203.0.113.10 | 4 | 4G | 64G | 105 | Samba4 AD DC primaire |
| **ad-server-2** | 20 | 203.0.113.13 | 4 | 4G | 64G | 106 | Samba4 AD DC secondaire (réplication) |
| **dhcp-server** | 20 | 203.0.113.11 | 2 | 2G | 32G | 107 | Kea DHCP + DNS forwarder |
| **dhcp-server-2** | 20 | 203.0.113.14 | 2 | 2G | 32G | 108 | Kea DHCP HA pair |
| **vault-server** | 20 | 203.0.113.12 | 2 | 2G | 32G | 109 | Vaultwarden gestionnaire de mots de passe |
| **keycloak-server** | 20 | 203.0.113.20 | 2 | 2G | 32G | 110 | Keycloak SSO IdP primaire |
| **keycloak-server-2** | 20 | 203.0.113.23 | 2 | 2G | 32G | 111 | Keycloak SSO IdP secondaire |
| **step-ca-server** | 20 | 203.0.113.21 | 1 | 512M | 16G | 112 | Smallstep step-ca PKI interne |
| **collab-server** | 30 | 203.0.113.60 | 4 | 8G | 128G | 113 | Nextcloud + OnlyOffice |
| **mail-server** | 30 | 203.0.113.61 | 2 | 2G | 64G | 114 | Postfix + Dovecot |
| **test-client** | 40 | 203.0.113.100 | 2 | 4G | 64G | 115 | Ubuntu Desktop — validation SSO/Kerberos |
| **dmz-proxy** | 50 | 203.0.113.70 | 2 | 2G | 32G | 116 | nginx reverse proxy + ModSecurity WAF |
| **haproxy-1** | 50 | 203.0.113.80 | 1 | 1G | 16G | 117 | HAProxy LB primaire (VRRP) |
| **haproxy-2** | 50 | 203.0.113.81 | 1 | 1G | 16G | 118 | HAProxy LB backup (VRRP) |

### Services sur le PC hôte

| Service | Port | Rôle |
|---------|------|------|
| Forgejo | 3000 | Usine logicielle privée (Git + CI/CD Actions) |
| LocalStack | 4566 | Simulation AWS S3 + IAM |
| OpenCode | — | Agent IA (GLM 5.1) + serveurs MCP |
| Forgejo Runner | — | CI/CD runner (systemd user service, Docker containers) |

### Forgejo Runner — Service systemd user

Le Forgejo Runner s'exécute désormais sur le PC hôte en tant que service systemd user (anciennement LXC 120, supprimé).

| Propriété | Valeur |
|-----------|--------|
| Service | `forgejo-runner.service` (systemd user) |
| Configuration | `/opt/asip/.runner-home/config.yaml` |
| Unit file | `/home/admin/.config/systemd/user/forgejo-runner.service` |
| Gestion | `systemctl --user start/stop/status forgejo-runner.service` |
| Mode d'exécution | Docker containers (`docker://node:22-bookworm`) |
| Labels | `ubuntu-latest:docker://node:22-bookworm`, `ansible:docker://node:22-bookworm` |

---

## Segmentation réseau

### VLANs

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PROXMOX VE — vmbr0                          │
│                                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │  VLAN 10    │  │  VLAN 20    │  │  VLAN 30    │  │ VLAN 50  │ │
│  │  MANAGEMENT │  │  SERVICES   │  │  COLLAB     │  │   DMZ    │ │
│  │ 203.0.113.0/28 │  │ 203.0.113.16/28 │  │ 203.0.113.32/28 │  │203.0.113.64/28  │ │
│  │             │  │             │  │             │  │  /24     │ │
│  │ bastion     │  │ AD DC 1+2   │  │ Nextcloud   │  │ nginx    │ │
│  │ monitoring  │  │ DHCP 1+2    │  │ OnlyOffice  │  │ WAF      │ │
│  │ pg-node 1-3 │  │ Vaultwarden │  │ Mail        │  │ HAProxy  │ │
│  │ mcp-watchdog│  │ Keycloak 1+2│  │             │  │ 1+2      │ │
│  │             │  │ step-ca     │  │             │  │          │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └────┬─────┘ │
│         │                │                │               │        │
│  ┌──────┴────────────────┴────────────────┴───────────────┴──┐    │
│  │              OPNsense Router (Inter-VLAN routing)         │    │
│  │     Primary: 203.0.113.1 / Backup: 203.0.113.2 / VIP: .254 │    │
│  └───────────────────────────────────────────────────────────┘    │
│                             │                                      │
│                       vmbr0 (WAN)                                 │
│                             │                                      │
└─────────────────────────────┼──────────────────────────────────────┘
                              │
                         Réseau local
                              │
                   ┌──────────┴──────────┐
                   │      PC HOTE        │
                   │ Forgejo + LocalStack│
                   └─────────────────────┘

  ┌─────────────┐
  │  VLAN 40    │  (isolation complète, pas de route vers MGMT)
  │  CLIENTS    │
  │ 203.0.113.48/28 │
  │ test-client │
  └─────────────┘
```

### Matrice de flux inter-VLAN

| Source | Destination | Protocole:Ports | Service |
|--------|-------------|-----------------|---------|
| Clients (40) | Services (20) | TCP:53,88,135,139,389,445,464,636,3268,3269 | Auth AD |
| Clients (40) | Services (20) | UDP:53,88,123,137,138,389,464 | DNS/Kerberos/NTP |
| Clients (40) | Services (20) | TCP:443 | Vaultwarden |
| Clients (40) | Collab (30) | TCP:443,444 | Nextcloud/OnlyOffice |
| Clients (40) | Collab (30) | TCP:587,993 | Mail SMTP/IMAP |
| Collab (30) | Services (20) | TCP:636,88,389,445 | LDAP/Kerberos/SMB |
| Services (20) | Management (10) | TCP:22 | Ansible SSH |
| MCP-Watchdog (10) | Toutes VMs | TCP:22 | Surveillance + remediation |
| MCP-Watchdog (10) | PC Hôte | TCP:4566 | Accès LocalStack S3 |
| DMZ (50) | Collab (30) | TCP:443,444 | Reverse proxy |
| DMZ (50) | Services (20) | TCP:8443 | Proxy vers Keycloak |
| **Interdit** | Clients → Management | ALL | Isolation stricte |
| **Interdit** | DMZ → Management | ALL | DMZ ne touche pas MGMT |

---

## Haute Disponibilité

| Service | Mécanisme HA | VIP / Failover |
|---------|-------------|----------------|
| Firewall/Routing | OPNsense CARP | 203.0.113.x.254 |
| AD Directory | Samba4 réplication multi-DC | ad-server + ad-server-2 |
| DHCP | Kea HA active-active | dhcp-server + dhcp-server-2 |
| PostgreSQL | Patroni (3 nœuds, automatic failover) | 203.0.113.30-32 |
| SSO | Keycloak HA pair | keycloak-server + keycloak-server-2 |
| Load Balancing | HAProxy + VRRP (Keepalived) | haproxy-1 (primary) + haproxy-2 (backup) |

---

## Stockage hybride (SIMULATE)

Le stockage hybride est la brique "SIMULATE" d'A.S.I.P. Il simule un scénario de cloud hybride On-Premise + AWS S3, entièrement en local via LocalStack.

```
┌───────────────────────┐          ┌──────────────────────┐
│   INFRA ON-PREM       │          │   LOCALSTACK (Mock)  │
│                       │          │                      │
│  vault-server         │  rclone  │  asip-backup (S3)    │
│  203.0.113.12          │ ──────── │  Versioning+Lifecycle│
│                       │  sync    │                      │
│  collab-server        │ ──────── │  asip-documents (S3)  │
│  203.0.113.60          │  sync    │  Versioning+Lifecycle│
│                       │          │                      │
│  mcp-watchdog         │ ──────── │  IAM users/policies  │
│  203.0.113.50      │  boto3   │  (asip-backup-agent) │
│  (LXC)                │          │                      │
│                       │          │  asip-terraform-state│
│                       │          │  (S3, AES256)         │
│                       │          │                      │
│                       │          │  IAM: asip-watchdog   │
│                       │          │  (access to asip-*)  │
└───────────────────────┘          └──────────────────────┘
        │                                    ▲
        │  VLAN 10/20/30                     │ localhost:4566
        └────────── Réseau local ────────────┘
```

### Politique de réplication

| Bucket LocalStack | Source On-Prem | Fréquence | Rétention |
|-------------------|---------------|-----------|-----------|
| `asip-backup` | Vaults + configs Ansible | Quotidien (cron 02:00) | 30 jours |
| `asip-documents` | Documents Nextcloud | Temps réel (rclone sync) | 90 jours |
| `asip-terraform-state` | État Terraform (lock + state) | À chaque apply | Indéfini (versionné) |

### IAM LocalStack

| Utilisateur | Rôle | Accès |
|-------------|------|-------|
| `asip-backup-agent` | Sauvegarde automatisée | s3:FullAccess sur `asip-backup` |
| `asip-docs-sync` | Synchronisation documents | s3:PutObject, s3:GetObject sur `asip-documents` |
| `asip-cross-account` | Scénario cross-account | sts:AssumeRole sur `asip-cross-account-role` |
| `asip-watchdog` | Agent IA surveillance | s3:FullAccess sur `asip-*`, lecture état infrastructure |

**Note** : mcp-watchdog est un **container LXC** (VMID 119), pas une VM QEMU. Terraform crée la VM via `proxmox_virtual_environment_vm` mais l'infrastructure réelle déploie un LXC via les scripts Ansible. Le LXC permet une empreinte plus légère et un accès direct au kernel de l'hôte pour les vérifications Goss. Le VMID 119 référence le container LXC sur le node Proxmox.

### rclone Remotes

Les VMs utilisent deux remotes rclone configurés par le rôle Ansible `hybrid-storage` :

| Remote | Endpoint | Usage |
|--------|----------|-------|
| `localstack` | `http://localhost:4566` | Accès S3 LocalStack (mock, dev/test) |
| `asip-s3` | `http://localhost:4566` | Accès S3 LocalStack (production-like), même endpoint, credentials IAM dédiés |

---

## Dépendances de déploiement

L'ordre de déploiement respecte les dépendances entre composants :

```
1. OPNsense Router (VLANs, routing, DHCP relay, NAT)
   │
   ├── 2a. AD Server (Kerberos, DNS, LDAP) ──────────────┐
   │   ├── 2b. AD Server 2 (réplication)                  │
   │   └── 2c. step-ca (PKI, certificats)                │
   │                                                       │
   ├── 3a. DHCP Server (Kea) ───────────────────────────┤ Déploiement
   │   └── 3b. DHCP Server 2 (HA pair)                    │ parallèle
   │                                                       │
   ├── 4. PostgreSQL Patroni (3 nœuds) ─────────────────┤
   │                                                       │
   ├── 5a. Keycloak (SSO) + Keycloak 2 ─────────────────┤
   │   └── 5b. Vaultwarden                                │
   │                                                       │
   ├── 6. Nextcloud + OnlyOffice + Mail ────────────────┤
   │                                                       │
     ├── 7. Monitoring (Prometheus, Grafana, Loki)         │
     │   └── Forgejo Runner (PC hôte, v0.2.11, Docker)     │
     │                                                       │
     ├── 8. DMZ (nginx WAF + HAProxy) ────────────────────┤
    │                                                       │
    ├── 9. Domain Join (tous les serveurs) ───────────────┤
    │                                                       │
    ├── 10. Sécurité (Trivy, Goss, CrowdSec, AIDE) ──────┤
    │                                                       │
     └── 11. A.S.I.P. Additions                            │
         ├── MCP Watchdog (LXC 119 + agent)                  │
         ├── Forgejo Runner (PC hôte, systemd user)           │
         ├── Hybrid Storage (rclone + LocalStack)           │
         └── Forgejo Actions Workflows                      │
```

---

## Canaux de communication

| Canal | Protocole | De | Vers | Usage |
|-------|-----------|-----|------|-------|
| SSH | TCP:22 | Ansible/MCP → VMs | Toutes VMs | Provisionnement + remediation |
| MCP (stdio) | JSON-RPC | OpenCode → MCP servers | Proxmox, Ansible, Watchdog | Contrôle IA |
| HTTPS | TCP:443 | Clients → DMZ | Proxy/LB | Accès services |
| LDAPS | TCP:636 | Services → AD | ad-server | Auth LDAP |
| Kerberos | TCP/UDP:88 | Toutes VMs → AD | ad-server | Auth SSO |
| Webhook | TCP:8080 | VMs → Watchdog | mcp-watchdog (203.0.113.50) | Alertes drift |
| S3 API | TCP:4566 | VMs → LocalStack | localhost | Stockage hybride |
| Forgejo API | TCP:3000 | Runner → Forgejo | PC hôte (localhost) | CI/CD |