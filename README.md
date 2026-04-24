# A.S.I.P. (Autonomous Sovereign Infrastructure Platform)

> Infrastructure autonome et souveraine deployee, securisee et maintenue par IA

---

## Badges

![Terraform](https://img.shields.io/badge/Terraform-1.9.8-7B42BC?logo=terraform)
![Ansible](https://img.shields.io/badge/Ansible-2.16-EE0000?logo=ansible)
![Proxmox](https://img.shields.io/badge/Proxmox%20VE-8.2-E57000?logo=proxmox)
![LocalStack](https://img.shields.io/badge/LocalStack-3.x-0A0?logo=amazon-aws)
![MCP](https://img.shields.io/badge/MCP-Protocol-0058CC)
![GLM](https://img.shields.io/badge/GLM-5.1-green)
![Forgejo](https://img.shields.io/badge/Forgejo-14.x-FA6D24)
![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%2F24.04-E95420?logo=ubuntu)
![License](https://img.shields.io/badge/License-Open--Source-green)
![CI Status](https://img.shields.io/badge/CI-passing-brightgreen)
![Security](https://img.shields.io/badge/security-Trivy%20Shift%20Left-blue)
![Branch](https://img.shields.io/badge/branch%20protection-required%201%20review-blue)

---

## Description

A.S.I.P. resout deux problematiques critiques de l'industrie IT : le **Toil** operationnel (taches repetitives et sans valeur ajoutee) et la perte de **souverainete numerique** face aux clouds proprietaires.

Infrastructure autonome deployee sur Proxmox VE, cette plateforme orchestre un environnement complet -- 19 VMs, 1 LXC, 5 VLANs, stockage hybride et chaine CI/CD -- de maniere entierement automatisée. Le deploiement, la securisation et la maintenance sont supervises par des agents d'intelligence artificielle, le tout repose sur une stack 100 % Open Source et 100 % on-premise.

---

## Table des matieres

- [Description](#description)
- [Contexte](#contexte)
- [Vue d'ensemble de l'architecture](#vue-densemble-de-larchitecture)
- [Installation et prerequis](#installation-et-prerequis)
- [Utilisation / Demarrage rapide](#utilisation--demarrage-rapide)
- [Demonstration](#demonstration)
- [Fonctionnalites](#fonctionnalites)
- [Documentation](#documentation)
- [Contribuer](#contribuer)
- [Licence](#licence)

---

## Contexte

### Pourquoi ce projet ?

Les equipes operations et les PME font face a des defis recurrents :

| Probleme | Consequence | Reponse d'A.S.I.P. |
|----------|-----------|-------------------|
| Toil operationnel | Temps perdu en taches repetitives (deploiements, patching, audits manuels) | Automatisation end-to-end via Terraform, Ansible et agents IA |
| Dependance cloud | Cout croissant, lock-in vendor, gouvernance des donnees compromis | Stack 100 % on-premise simulant le cloud avec LocalStack |
| Securite tardive | Vulnerabilites detectees en production, corrections couteuses | Shift-left : scan Trivy et hardening ANSSI des le premier commit |
| Obsolescence silencieuse | Drift de configuration, dette technique invisible | Surveillance cyclique MCP + auto-remediation par Ansible |
| Manque de visibilite | Absence de supervision centralisee et d'alertes predictives | Plateforme unifiee avec logs, metriques et boucles de reaction automatisees |

A.S.I.P. est concu comme un environnement de production industriel reproductible : il integre l'infrastructure as code, la securisation native et des capacites d'autonomie operationnelle pilotees par LLM, le tout dans un cadre documente et totalement transparent.

---

## Vue d'ensemble de l'architecture

### Topologie reseau

```
                          PROXMOX VE (pve)                      
                          192.0.2.10                            
                                                                      
      +--------------------+  +--------------------+              
      |  VLAN 10 (MGMT)    |  |  VLAN 20 (SERVICES) |              
      |  203.0.113.0/24    |  |  203.0.113.0/24     |              
      |                    |  |                     |              
      |  +---------------+ |  |  +------+ +------+  |              
      |  |  bastion      | |  |  |  AD  | | DHCP |  |              
      |  |  .5           | |  |  |  .10 | | .11  |  |              
      |  +---------------+ |  |  +------+ +------+  |              
      |                    |  |                     |              
      |  +---------------+ |  |  +------+ +------+  |              
      |  | mcp-watchdog  | |  |  | Vault| | ...  |  |              
      |  | .50 (LXC)     | |  |  | .12  | |      |  |              
      |  +---------------+ |  |  +------+ +------+  |              
      +--------------------+  +--------------------+              
                                                                      
      +--------------------+  +--------------------+              
      |  VLAN 30 (COLLAB)  |  |  VLAN 40 (CLIENTS)  |              
      |  203.0.113.0/24    |  |  203.0.113.0/24     |              
      |                    |  |                     |              
      |  +---------------+ |  |  +---------------+    |              
      |  |  Nextcloud    | |  |  | test-client   |    |              
      |  |  .10          | |  |  | .100          |    |              
      |  +---------------+ |  |  +---------------+    |              
      |  +---------------+ |  |                     |              
      |  |  Mail         | |  +--------------------+              
      |  |  .11          | |                                      
      |  +---------------+ |  +--------------------+              
      +--------------------+  |  VLAN 50 (DMZ)     |              
                              |  203.0.113.0/24    |              
                              |                    |              
                              |  +------+ +--------+ |              
                              |  |Proxy | |HAProxy | |              
                              |  |.10   | |.20/.21 | |              
                              |  +------+ +--------+ |              
                              +--------------------+              
                                                                      
      +-------------------------------------------------+          
      |       OPNsense Router (CARP HA)                   |          
      |       Primary: 203.0.113.1                        |          
      |       Backup:  203.0.113.2                        |          
      |       CARP VIPs: .254                             |          
      +-------------------------------------------------+          
                              |                                      
                              | Reseau local                         
                              v                                      
      +-------------------------------------------------+          
      |                  PC HOTE                          |          
      |  +-----------+    +------------+                  |          
      |  | Forgejo   |    | LocalStack |                  |          
      |  | :3000     |    | :4566      |                  |          
      |  +-----------+    +------------+                  |          
      |  +-------------------------------------------+    |          
      |  | OpenCode (Agent IA + MCP)                 |    |          
      |  +-------------------------------------------+    |          
      |  +-------------------------------------------+    |          
      |  | Forgejo Runner (systemd user)             |    |          
      |  | docker://node:22-bookworm                  |    |          
      |  +-------------------------------------------+    |          
      +-------------------------------------------------+          
```

### Flux de donnees CI/CD et auto-remediation

```
  git push ---> Forgejo :3000
                  |
        +---------+----------+
        v         v          v
  security-scan  deploy   drift-check
  (Trivy)     (Tf+Ans)   (Goss)
        |         |          |
        +----> Pass? <-------+
                  |
            +-----+-----+
            |    Oui    | Non ---> Bloque le merge
            v
     Infra deployee
            |
     Goss timer (5 min)
            |
     +------v-------+
     | MCP Watchdog | <--- POST /webhook (si drift)
     | 203.0.113.50 |
     +------+-------+
            |
     Drift detecte ?
     +-- Oui ---> ansible-playbook --tags <role> (auto-remediation)
     |
     +-- Non ---> Log + notification
```

---

## Installation et prerequis

### Stack technique requise

| Composant | Version | Role |
|-----------|---------|------|
| Proxmox VE | 8.2+ | Hyperviseur et orchestration des VMs |
| Terraform | 1.9.8+ | Infrastructure as Code (IaC) |
| Ansible | 2.16+ | Configuration management |
| Forgejo | 14.x | Forge logicielle et CI/CD Actions |
| LocalStack | 3.x | Simulation AWS (S3, IAM) en local |
| Python | 3.11+ | Runtime des agents MCP et watchdog |
| GLM | 5.1 | Modele de langage pour l'autonomie operationnelle |
| OS (VMs) | Ubuntu Server 24.04 | Systeme d'exploitation des machines |
| OS (LXC) | Ubuntu Server 22.04 | Systeme du container mcp-watchdog |

### Pre-requis materiels et logiciels

- Node Proxmox accessible avec API token (`root@pam!terraform`)
- Templates cloud-init disponibles : Ubuntu 22.04 (VMID 8000) et Ubuntu 24.04 (VMID 9000)
- Docker et Docker Compose fonctionnels sur le poste operateur
- Accus SSH au reseau `203.0.113.0/24`
- Forgejo accessible localement sur `http://localhost:3000`

---

## Utilisation / Demarrage rapide

### 1. Demarrer LocalStack

```bash
cd localstack/
docker compose up -d
# Attendre que LocalStack soit pret
curl -s http://localhost:4566/_localstack/health | jq .
```

### 2. Deployer l'infrastructure Terraform

```bash
cd terraform/
terraform init
terraform plan -var-file=environments/prod.tfvars -parallelism=1 -out=tfplan
terraform apply -parallelism=1 -auto-approve tfplan
```

### 3. Provisionner avec Ansible

```bash
cd ansible/
ansible-playbook -i inventory/prod.yml site.yml \
  --private-key ~/.ssh/id_ed25519 -u ansible -b
```

### 4. Ou tout-en-un

```bash
./scripts/deploy.sh all
```

### 5. Verifier

```bash
./scripts/verify.sh
```

---

## Demonstration

Le repertoire `scripts/` contient des scenarios de demonstration permettant de valider les capacites autonomes et hybrides de la plateforme.

### Auto-remediation suite a un drift

Le script `scripts/demo-autonomous.sh` simule une modification non autorisee (drift) sur une VM cible, puis met en evidence la detection et la correction automatique par l'agent MCP.

```bash
./scripts/demo-autonomous.sh
```

**Ce que prouve cette demonstration :**

- L'agent `mcp-watchdog` (LXC, VMID 119, IP 203.0.113.50) surveille en continu l'etat du parc.
- Toute derive de configuration est detectee via Goss et signalee au controleur MCP.
- Un playbook Ansible cible est declenche automatiquement pour restaurer l'etat desire.
- Aucune intervention humaine n'est requise pour corriger un ecart standard.

### Stockage hybride simule

Le script `scripts/simulate-hybrid.sh` met en oeuvre la synchronisation de donnees entre un stockage local (NFS/SMB simule sur site) et un stockage objet S3 simule via LocalStack.

```bash
./scripts/simulate-hybrid.sh
```

**Ce que prouve cette demonstration :**

- La possibilite d'implementer un tiering de donnees sans dependance a un cloud public.
- La validation du pipeline de replication (LocalStack S3 + rclone).
- La continuite de la configuration IAM et des buckets en environnement isole.

---

## Fonctionnalites

### Les 4 piliers

| Pilier | Description | Preuve concrete |
|--------|-------------|-----------------|
| **DEPLOY** | Deploiement Zero-Touch d'un environnement complet | Commande unique `./scripts/deploy.sh all` provisionne 19 VMs + 1 LXC |
| **SECURE** | Securite Shift-Left : scan des la phase de developpement | Scan Trivy au push, hardening ANSSI (CIS Benchmark), Goss compliance, CrowdSec |
| **SIMULATE** | Simulation d'un stockage hybride On-Premise + AWS | LocalStack S3/IAM + rclone pour synchroniser les donnees sans connexion externe |
| **AUTONOMOUS OPS** | Agent IA surveillant l'infrastructure et remediait automatiquement | Container LXC `mcp-watchdog` (VMID 119, IP 203.0.113.50) detecte le drift et declenche Ansible |

### Haute disponibilite

- **Routage** : CARP et VRRP sur OPNsense (Primary 203.0.113.1, Backup 203.0.113.2)
- **Bases de donnees** : Replication Patroni (PostgreSQL HA)
- **DHCP** : Kea en configuration haute disponibilite

---

## Documentation

La documentation complete du projet est disponible dans le repertoire `docs/` :

| Document | Contenu |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Vue d'ensemble technique detaillee |
| [docs/SECURITY.md](docs/SECURITY.md) | Strategie de securite (ANSSI, CIS, shift-left) |
| [docs/AUTONOMOUS-OPS.md](docs/AUTONOMOUS-OPS.md) | Agent MCP Watchdog, auto-remediation |
| [docs/CI-CD.md](docs/CI-CD.md) | Pipeline Forgejo Actions, branch protection |
| [docs/OPERATOR-GUIDE.md](docs/OPERATOR-GUIDE.md) | Runbook quotidien, procedures d'urgence |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Erreurs courantes et solutions |
| [docs/LOCALSTACK.md](docs/LOCALSTACK.md) | Configuration du stockage hybride simule |
| [docs/DEMO-SCRIPT.md](docs/DEMO-SCRIPT.md) | Script de demonstration detaille |

---

## Contribuer

Les contributions sont les bienvenues. Toute amelioration apportant de la robustesse, de la clarte documentaire ou de nouvelles integrations IA sera examinee avec interet pour renforcer la plateforme.

1. Forkez le depot
2. Creez une branche fonctionnelle (`git checkout -b feature/nom-de-la-feature`)
3. Commitez vos changements (`git commit -m 'Ajout de ...'`)
4. Poussez vers la branche (`git push origin feature/nom-de-la-feature`)
5. Ouvrez une Merge Request sur Forgejo

---

## Licence

Tous les composants utilises par A.S.I.P. sont Open Source :

| Composant | Licence |
|-----------|---------|
| Proxmox VE | AGPL-3 |
| Terraform | BSL-1.1 |
| Ansible | GPL-3 |
| Forgejo | AGPL-3 |
| LocalStack | Apache-2.0 |
| Goss | Apache-2.0 |
| Trivy | Apache-2.0 |
| GLM 5.1 | Apache-2.0 |

Le projet lui-meme est publie sous licence Open Source. Les contributions restent la propriete de leurs auteurs respectifs.

---

*Autonomous Sovereign Infrastructure Platform*
