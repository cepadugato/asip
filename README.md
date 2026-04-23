# A.S.I.P. — Architecture de Securite d'Infrastructure Pilotee par IA

> **Automatisation et Securisation d'Infrastructures dans un contexte de Cloud Souverain**

---

## Présentation

A.S.I.P. est un projet démontrant qu'une infrastructure complète peut être **déployée**, **sécurisée** et **maintenue** par une équipe d'agents IA supervisée par un ingénieur. Le projet repose sur des technologies 100 % Open Source et hébergeables localement, garantissant une **souveraineté numérique totale**.

## Les 4 piliers

| Pilier | Fonction | Technologies |
|--------|----------|--------------|
| **DEPLOY** | Déploiement "Zero-Touch" d'un environnement complet | Terraform, Ansible, Cloud-init, Proxmox VE |
| **SECURE** | Scan de vulnérabilités automatique dès le push (Shift-Left) | Forgejo Actions, Trivy, Goss, Hardening ANSSI |
| **SIMULATE** | Simulation du stockage hybride On-Premise + AWS | LocalStack (S3/IAM), rclone, Terraform |
| **AUTONOMOUS OPS** | Agent IA surveillant l'infra via MCP, auto-remédiation | MCP Protocol, FastAPI, GLM 5.1, Goss, Ansible |

## Stack technique

| Composant | Technologie | Rôle |
|-----------|-------------|------|
| Hyperviseur | Proxmox VE 8.2 | Gestion de VMs et ressources locales |
| IaC | Terraform + Ansible | Provisionnement et configuration |
| CI/CD & Git | Forgejo 14.x | Usine logicielle privée + Actions |
| Cloud Mocking | LocalStack 3.x | Simulation AWS S3/IAM en local |
| IA Agentique | LLM GLM 5.1 + MCP | Surveillance et auto-remédiation |
| OS | Ubuntu Server 22.04 (LXC), 24.04 (VMs) | Systèmes d'exploitation |
| Sécurité | Trivy, Goss, CrowdSec, AIDE | Scans, conformité, détection d'intrusion |
| CI/CD Runner | Forgejo Runner v0.2.11 | Exécution des workflows CI/CD |

## Architecture réseau

```
                       ┌─────────────────────────────────────┐
                       │         PROXMOX VE (pve)            │
                       │         192.168.100.254              │
                       │                                     │
    VLAN 10 (MGMT)     │  ┌──────────┐  ┌───────────────┐    │
    10.10.10.0/24      │  │ bastion  │  │ mcp-watchdog  │    │
                       │  │  .5      │  │ .119 (LXC)    │    │
                       │  └──────────┘  └───────────────┘    │
                       │  ┌──────────────────────────────┐   │
                       │  │ forgejo-runner (LXC 120)     │   │
                       │  │ 192.168.100.120               │   │
                       │  └──────────────────────────────┘   │
                       │                        │             │
    VLAN 20 (SERVICES) │  ┌──────┐ ┌──────┐ ┌──────┐       │
    10.10.20.0/24      │  │ AD   │ │ DHCP │ │Vault │ ...    │
                       │  │ .10  │ │ .11  │ │ .12  │       │
                       │  └──────┘ └──────┘ └──────┘       │
                       │                                     │
    VLAN 30 (COLLAB)   │  ┌──────────┐  ┌──────────┐       │
    10.10.30.0/24      │  │Nextcloud │  │  Mail    │       │
                       │  │  .10     │  │  .11     │       │
                       │  └──────────┘  └──────────┘       │
                       │                                     │
    VLAN 40 (CLIENTS)  │  ┌──────────────┐                  │
    10.10.40.0/24      │  │ test-client  │                  │
                       │  │  .100        │                  │
                       │  └──────────────┘                  │
                       │                                     │
    VLAN 50 (DMZ)      │  ┌───────┐  ┌────────┐            │
    10.10.50.0/24      │  │ Proxy │  │HAProxy │            │
                       │  │ .10   │  │ .20/.21│            │
                       │  └───────┘  └────────┘            │
                       │                                     │
                       │  ┌─────────────────────────────┐   │
                       │  │ OPNsense Router (CARP HA)   │   │
                       │  │ Primary: 10.10.20.1         │   │
                       │  │ Backup:  10.10.20.2         │   │
                       │  │ CARP VIPs: .254             │   │
                       │  └─────────────────────────────┘   │
                       └─────────────────────────────────────┘
                                       │
                                       │Réseau local
                                       ▼
                       ┌─────────────────────────────────────┐
                       │          PC HOTE                    │
                       │  ┌───────────┐  ┌──────────────┐   │
                       │  │ Forgejo   │  │ LocalStack   │   │
                       │  │ :3000     │  │ :4566        │   │
                       │  └───────────┘  └──────────────┘   │
                       │  ┌───────────────────────────────┐  │
                       │  │ OpenCode (Agent IA + MCP)     │  │
                       │  └───────────────────────────────┘  │
                       └─────────────────────────────────────┘
```

## Flux de données

```
  git push ──► Forgejo :3000
                  │
        ┌─────────┼──────────┐
        ▼         ▼          ▼
  security-scan  deploy   drift-check
  (Trivy)     (Tf+Ans)   (Goss)
        │         │          │
        └─────► Pass? ───────┘
                   │
              ┌────┴────┐
              │  Oui    │ Non ──► Bloque le merge
              ▼         
       Infra déployée
              │
       Goss timer (5 min)
              │
       ┌──────▼──────┐
        │  MCP Watchdog│ ◄── POST /webhook (si drift)
        │(192.168.100.119)
        └──────┬──────┘
              │
       Drift detecté?
       ├── Oui ──► ansible-playbook --tags <role> (auto-remediation)
       └── Non  ──► Log + notification
```

## Structure du projet

```
asip/
├── terraform/                    # IaC — déploiement VM mcp-watchdog
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── environments/
│       └── prod.tfvars
├── ansible/
│   ├── site.yml                  # Playbook principal ASIP
│   ├── inventory/
│   │   └── prod.yml             # Inventaire étendu
│   └── roles/
│       ├── mcp-watchdog/        # Agent de surveillance IA
│       └── hybrid-storage/     # Stockage hybride On-Prem ↔ S3
├── localstack/
│   ├── docker-compose.yml        # LocalStack S3 + IAM
│   ├── init/                    # Initialization hooks
│   │   ├── 01-create-buckets.sh
│   │   └── 02-create-iam.sh
│   └── terraform/               # IaC pour ressources LocalStack
│       ├── main.tf
│       └── variables.tf
├── .forgejo/
│   └── workflows/               # CI/CD Forgejo Actions
│       ├── security-scan.yml
│       ├── drift-check.yml
│       ├── terraform-deploy.yml
│       └── ansible-deploy.yml
├── mcp-agent/
│   ├── server.py                # Serveur MCP watchdog
│   ├── watchdog/
│   │   ├── poller.py            # Polling cyclique Goss/Trivy
│   │   ├── webhook_listener.py # Récepteur webhooks FastAPI
│   │   ├── remediation.py      # Déclencheur Ansible
│   │   └── state.py           # État de surveillance
│   ├── requirements.txt
│   └── config.yaml
├── scripts/
│   ├── deploy.sh                # Point d'entrée unique
│   ├── verify.sh                # Validation post-déploiement
│   ├── simulate-hybrid.sh       # Demo stockage hybride
│   └── demo-autonomous.sh       # Demo auto-remédiation
└── docs/
    ├── ARCHITECTURE.md          # Architecture détaillée
    ├── SECURITY.md              # Stratégie de sécurité ANSSI
    ├── AUTONOMOUS-OPS.md        # Opérations autonomes IA
    ├── DEMO-SCRIPT.md           # Script de démonstration
    ├── LOCALSTACK.md            # Guide LocalStack
    └── CI-CD.md                 # Guide CI/CD Forgejo
```

## Démarrage rapide

### Prérequis

- Proxmox VE 8.2+ avec template Ubuntu 22.04 cloud-init (LXC) et Ubuntu 24.04 cloud-init (VMID 9000)
- Docker + Docker Compose sur le PC hôte
- Terraform 1.8+, Ansible 2.16+, Python 3.11+
- Forgejo fonctionnel sur `localhost:3000`
- Accès SSH au réseau `192.168.100.0/24`

### 1. Démarrer LocalStack

```bash
cd localstack/
docker compose up -d
# Attendre que LocalStack soit prêt
curl -s http://localhost:4566/_localstack/health | jq .
```

### 2. Déployer l'infrastructure Terraform

```bash
cd terraform/
terraform init
terraform plan -var-file=environments/prod.tfvars -parallelism=1 -out=tfplan
terraform apply -parallelism=1 -auto-approve tfplan
```

### 3. Provisionner avec Ansible

```bash
cd ansible/
ansible-playbook -i inventory/prod.yml site.yml --private-key ~/.ssh/id_ed25519 -u ansible -b
```

### 4. Ou tout-en-un

```bash
./scripts/deploy.sh all
```

### 5. Vérifier

```bash
./scripts/verify.sh
```

## Démons de valeur

| Argument | Réalisation A.S.I.P. |
|----------|----------------------|
| **Réduction du Toil** | Déploiement complet en 1 commande, auto-remédiation sans intervention |
| **Sécurité Native** | Hardening ANSSI (CIS Benchmark), Trivy shift-left, Goss compliance, CrowdSec |
| **Rentabilité** | 100 % Open Source, ressources locales, IA open-source, coût d'exploitation minimal |
| **Souveraineté** | Aucune dépendance cloud externe, LocalStack simule AWS sans y être connecté |

## Licences

Tous les composants utilisés sont Open Source :
- Proxmox VE (AGPL-3)
- Terraform (BSL-1.1), Ansible (GPL-3)
- Forgejo (MIT/AGPL-3)
- LocalStack (Apache-2.0)
- Goss (Apache-2.0), Trivy (Apache-2.0)
- GLM 5.1 (Apache-2.0)

## Auteurs

Projet A.S.I.P. — Équipe infra IA, 2026.