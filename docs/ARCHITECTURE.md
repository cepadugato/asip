# Architecture A.S.I.P.

## Vue d'ensemble

A.S.I.P. étend l'infrastructure Proxmox existante (21 VMs + 2 routeurs OPNsense) avec un agent de surveillance IA et une simulation de cloud hybride. L'architecture repose sur 3 zones : le cluster Proxmox (on-premise), le PC hôte (Forgejo + LocalStack), et le canal MCP entre les deux.

---

## Composants d'infrastructure

### Matrice des VMs

| VM | VLAN | IP | CPU | RAM | Disk | VMID | Rôle |
|----|------|----|-----|-----|------|------|------|
| **opnsense-router** | WAN + 10-50 | 10.10.20.1 | 2 | 2G | 16G | 99 | Firewall/routeur primaire (CARP) |
| **opnsense-router-2** | WAN + 10-50 | 10.10.20.2 | 2 | 2G | 16G | 98 | Firewall/routeur backup (CARP) |
| **bastion** | 10 | 10.10.10.5 | 1 | 1G | 16G | 100 | SSH bastion + step-ca CA |
| **monitoring-server** | 10 | 10.10.10.20 | 2 | 4G | 64G | 101 | Prometheus, Grafana, Loki, Forgejo Runner |
| **mcp-watchdog** | 10 | 10.10.10.50 | 2 | 4G | 32G | 119 | Agent IA de surveillance + auto-remédiation |
| **pg-node-1** | 10 | 10.10.10.30 | 2 | 4G | 64G | 102 | PostgreSQL Patroni nœud 1 |
| **pg-node-2** | 10 | 10.10.10.31 | 2 | 4G | 64G | 103 | PostgreSQL Patroni nœud 2 |
| **pg-node-3** | 10 | 10.10.10.32 | 2 | 4G | 64G | 104 | PostgreSQL Patroni nœud 3 |
| **ad-server** | 20 | 10.10.20.10 | 4 | 4G | 64G | 105 | Samba4 AD DC primaire |
| **ad-server-2** | 20 | 10.10.20.13 | 4 | 4G | 64G | 106 | Samba4 AD DC secondaire (réplication) |
| **dhcp-server** | 20 | 10.10.20.11 | 2 | 2G | 32G | 107 | Kea DHCP + DNS forwarder |
| **dhcp-server-2** | 20 | 10.10.20.14 | 2 | 2G | 32G | 108 | Kea DHCP HA pair |
| **vault-server** | 20 | 10.10.20.12 | 2 | 2G | 32G | 109 | Vaultwarden gestionnaire de mots de passe |
| **keycloak-server** | 20 | 10.10.20.20 | 2 | 2G | 32G | 110 | Keycloak SSO IdP primaire |
| **keycloak-server-2** | 20 | 10.10.20.23 | 2 | 2G | 32G | 111 | Keycloak SSO IdP secondaire |
| **step-ca-server** | 20 | 10.10.20.21 | 1 | 512M | 16G | 112 | Smallstep step-ca PKI interne |
| **collab-server** | 30 | 10.10.30.10 | 4 | 8G | 128G | 113 | Nextcloud + OnlyOffice |
| **mail-server** | 30 | 10.10.30.11 | 2 | 2G | 64G | 114 | Postfix + Dovecot |
| **test-client** | 40 | 10.10.40.100 | 2 | 4G | 64G | 115 | Ubuntu Desktop — validation SSO/Kerberos |
| **dmz-proxy** | 50 | 10.10.50.10 | 2 | 2G | 32G | 116 | nginx reverse proxy + ModSecurity WAF |
| **haproxy-1** | 50 | 10.10.50.20 | 1 | 1G | 16G | 117 | HAProxy LB primaire (VRRP) |
| **haproxy-2** | 50 | 10.10.50.21 | 1 | 1G | 16G | 118 | HAProxy LB backup (VRRP) |

### Services sur le PC hôte

| Service | Port | Rôle |
|---------|------|------|
| Forgejo | 3000 | Usine logicielle privée (Git + CI/CD Actions) |
| LocalStack | 4566 | Simulation AWS S3 + IAM |
| OpenCode | — | Agent IA (GLM 5.1) + serveurs MCP |

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
│  │ 10.10.10/24 │  │ 10.10.20/24 │  │ 10.10.30/24 │  │10.10.50  │ │
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
│  │     Primary: 10.10.20.1 / Backup: 10.10.20.2 / VIP: .254 │    │
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
  │ 10.10.40/24 │
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
| Firewall/Routing | OPNsense CARP | 10.10.{10,20,30,40,50}.254 |
| AD Directory | Samba4 réplication multi-DC | ad-server + ad-server-2 |
| DHCP | Kea HA active-active | dhcp-server + dhcp-server-2 |
| PostgreSQL | Patroni (3 nœuds, automatic failover) | 10.10.10.30-32 |
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
│  10.10.20.12          │ ──────── │  Versioning+Lifecycle│
│                       │  sync    │                      │
│  collab-server        │ ──────── │  asip-documents (S3)  │
│  10.10.30.10          │  sync    │  Versioning+Lifecycle│
│                       │          │                      │
│  mcp-watchdog         │ ──────── │  IAM users/policies  │
│  10.10.10.50          │  boto3   │  (asip-backup-agent) │
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

### IAM LocalStack

| Utilisateur | Rôle | Accès |
|-------------|------|-------|
| `asip-backup-agent` | Sauvegarde automatisée | s3:FullAccess sur `asip-backup` |
| `asip-docs-sync` | Synchronisation documents | s3:PutObject, s3:GetObject sur `asip-documents` |
| `asip-cross-account` | Scénario cross-account | sts:AssumeRole sur `asip-backup-role` |

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
   │   └── Forgejo Runner (act_runner)                    │
   │                                                       │
   ├── 8. DMZ (nginx WAF + HAProxy) ────────────────────┤
   │                                                       │
   ├── 9. Domain Join (tous les serveurs) ───────────────┤
   │                                                       │
   ├── 10. Sécurité (Trivy, Goss, CrowdSec, AIDE) ──────┤
   │                                                       │
   └── 11. A.S.I.P. Additions                            │
       ├── MCP Watchdog (VM + agent)                      │
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
| Webhook | TCP:8080 | VMs → Watchdog | mcp-watchdog | Alertes drift |
| S3 API | TCP:4566 | VMs → LocalStack | localhost | Stockage hybride |
| Forgejo API | TCP:3000 | Runner → Forgejo | localhost | CI/CD |