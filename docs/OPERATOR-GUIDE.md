# Guide de l'Operateur A.S.I.P.

> Document a destination des operateurs chargés du deploiement, de la verification et de la maintenance de l'infrastructure A.S.I.P.

---

## 1. Vue d'ensemble (5 min)

A.S.I.P. (Architecture de Securite d'Infrastructure Pilotee par IA) est un projet d'infrastructure complete, 100 % Open Source et hebergee localement, qui demontre le deploiement, la securisation et la maintenance automatisée par une equipe d'agents IA supervisee par un ingenieur.

Le projet repose sur quatre piliers : le deploiement automatise (Terraform, Ansible, Proxmox), la securisation native (Trivy, Goss, hardening ANSSI), la simulation de cloud hybride (LocalStack S3/IAM) et les operations autonomes (MCP Watchdog avec auto-remediation).

| Composant | Technologie | IP / Endpoint |
|-----------|-------------|---------------|
| Hyperviseur | Proxmox VE 8.2 | 192.0.2.254 |
| Routeur / Firewall | OPNsense (HA CARP) | 203.0.113.1 / .2 (VIP .254) |
| Bastion | Ubuntu Server | 203.0.113.5 |
| Supervision | Grafana + Prometheus + Loki | 203.0.113.20:3000 |
| Keycloak | Serveur IAM | 203.0.113.20:8443 |
| Nextcloud | Cloud collaboratif | 203.0.113.110 |
| Vaultwarden | Gestionnaire de mots de passe | 203.0.113.112 |
| MCP Watchdog | Agent IA autonome | 203.0.113.50:8080 |
| Forgejo | Forge Git + CI/CD | localhost:3000 |
| LocalStack | Simulation AWS S3/IAM | localhost:4566 |

---

## 2. Prerequis

### Materiel

- Serveur Proxmox VE 8.2+ avec template Ubuntu 22.04 cloud-init (LXC) et Ubuntu 24.04 cloud-init (VMID 9000)
- PC hote avec CPU multi-coeurs, 16 Go RAM minimum, 50 Go disque disponible
- Switch gerable supportant 5 VLANs ou OPNsense en configuration router-on-a-stick

### Logiciels

| Outil | Version minimale | Verification |
|-------|-------------------|--------------|
| Terraform | 1.9.8+ | `terraform version` |
| Ansible | 2.16+ | `ansible --version` |
| Python | 3.11+ | `python3 --version` |
| Docker + Docker Compose | 24.0+ | `docker compose version` |
| Forgejo | 14.x | Accessible sur `localhost:3000` |
| rclone | 1.60+ | `rclone version` |

### Reseau

5 VLANs configures sur le switch ou via OPNsense :

| VLAN | Fonction | Plage IP |
|------|----------|----------|
| 10 | Management | 203.0.113.0/24 |
| 20 | Services | 203.0.113.0/24 |
| 30 | Collaboration | 203.0.113.0/24 |
| 40 | Clients | 203.0.113.0/24 |
| 50 | DMZ | 203.0.113.0/24 |

### Secrets

Avant tout deploiement, verifier la presence des elements suivants :

- Cle SSH Ed25519 : `~/.ssh/id_ed25519` (utilisee par Ansible)
- Token Proxmox API : `root@pam!terraform=<token>` (export `PROXMOX_API_TOKEN`)
- Mot de passe Ansible Vault : `~/.vault_pass` (genere par `./infra-proxmox/scripts/generate-vault.sh`)
- Credentials OPNsense : dans `ansible/group_vars/all/vault.yml`

---

## 3. Deploiement initial (30-60 min)

### Etape 1 : LocalStack

```bash
cd localstack && docker compose up -d
curl -sf http://localhost:4566/_localstack/health
```

Resultat attendu : JSON indiquant `S3`, `IAM` et `STS` a l'etat `running`.

### Etape 2 : Infrastructure existante (infra-proxmox)

```bash
cd ../infra-proxmox
./scripts/deploy.sh all
```

Ce script execute en sequence : generation du vault, preparation OPNsense, Terraform, demarrage du routeur, demarrage des VMs, attente SSH, provisioning Ansible, verification.

### Etape 3 : Infrastructure ASIP

```bash
cd ../asip
./scripts/deploy.sh all
```

OU etape par etape :

```bash
./scripts/deploy.sh prereqs    # Verifications
./scripts/deploy.sh localstack # Step 1
./scripts/deploy.sh infra      # Step 2
./scripts/deploy.sh asip-tf    # Step 3
./scripts/deploy.sh start      # Step 4
./scripts/deploy.sh provision  # Step 5
./scripts/deploy.sh verify     # Step 6
```

### Etape 4 : Verification

```bash
./scripts/verify.sh
```

Resultat attendu : `0 FAIL`. Le nombre de `PASS` depend du contexte (LocalStack, VMs, Forgejo, runner, etc.). En cas d'echec, consulter la section 6 (Procedures d'urgence).

---

## 4. Commandes quotidiennes

| Commande | Quand | Resultat attendu |
|----------|-------|------------------|
| `./scripts/verify.sh` | Post-deploiement, apres maintenance | `0 FAIL` |
| `curl http://203.0.113.50:8080/status` | verifier l'etat du watchdog | JSON avec etat des hotes (`OK` ou `DRIFT`) |
| `systemctl --user status forgejo-runner` | verifier le CI/CD | `active (running)` |
| `curl -sf http://localhost:4566/_localstack/health` | verifier LocalStack | JSON avec S3/IAM/STS `running` |
| `ansible-playbook ansible/site.yml --tags hardening --check -i ansible/inventory/prod.yml` | Dry-run hardening | Diff des changements, aucune modification appliquee |

---

## 5. Commandes de gestion

### Demarrer / Arreter des VMs

```bash
# Via CLI Proxmox (sur le noeud pve)
pm start 119   # MCP Watchdog
pm stop 119    # MCP Watchdog
pm status 119  # Voir etat

# Via API Proxmox (depuis le PC hote)
curl -sk -X POST "https://192.0.2.254:8006/api2/json/nodes/pve/qemu/119/status/start" \
  -H "Authorization: PVEAPIToken root@pam!terraform=<token>"

curl -sk -X POST "https://192.0.2.254:8006/api2/json/nodes/pve/qemu/119/status/stop" \
  -H "Authorization: PVEAPIToken root@pam!terraform=<token>"
```

Remplacer `119` par l'ID de la VM concernee.

### Gestion du watchdog

```bash
# SSH sur le watchdog
ssh ansible@203.0.113.50

# Voir les logs
cat /var/log/watchdog/watchdog.log

# Voir l'historique d'audit (JSON)
cat /var/log/watchdog/audit.json | python3 -m json.tool

# Redemarrer le service
sudo systemctl restart mcp-watchdog
sudo systemctl status mcp-watchdog

# Verifier Goss sur le watchdog lui-meme
sudo goss -g /etc/goss/goss.yaml validate

# Verifier Goss sur une VM distante (via bastion)
ssh ansible@203.0.113.5 "sudo goss -g /etc/goss/goss.yaml validate"
```

### Forcer une remediation manuelle

```bash
# Declencher la remediation via API du watchdog
curl -X POST http://203.0.113.50:8080/remediate/bastion

# Ou utiliser le serveur MCP (si connecte au client)
# Fonctionnalite disponible via le endpoint POST /remediate/{host}
```

### Gestion des secrets Ansible Vault

```bash
# Visualiser le vault
ansible-vault view ansible/group_vars/all/vault.yml --vault-password-file ~/.vault_pass

# Editer le vault
ansible-vault edit ansible/group_vars/all/vault.yml --vault-password-file ~/.vault_pass
```

### Gestion CI/CD

```bash
# Verifier le runner Forgejo (systemd --user)
systemctl --user status forgejo-runner

# Voir les logs en temps reel
journalctl --user -u forgejo-runner -f

# Arreter / demarrer le runner
systemctl --user stop forgejo-runner
systemctl --user start forgejo-runner

# Forcer un workflow
# Se connecter a l'UI Forgejo : http://localhost:3000
# Actions -> selectionner le workflow -> Run workflow
```

### Simulation du stockage hybride

```bash
# Tester le cycle backup S3 / restore local
./scripts/simulate-hybrid.sh
```

Resultat attendu : creation d'un fichier local, upload vers LocalStack S3, suppression locale, restauration depuis S3, verification du contenu.

### Demonstration des operations autonomes

```bash
# Injecte un drift (PermitRootLogin yes) et observe l'auto-remediation
./scripts/demo-autonomous.sh
```

---

## 6. Procedures d'urgence

### VM ne demarre pas

1. Verifier les ressources Proxmox :
   ```bash
   pvesh get /nodes/pve/status
   ```
2. Verifier la commande de boot :
   ```bash
   qm showcmd <vmid>
   ```
3. Verifier la configuration cloud-init :
   ```bash
   qm cloudinit dump <vmid> user
   ```
4. Consulter les logs KVM :
   ```bash
   qm console <vmid>
   ```

### Drift detecte non corrigé

1. Verifier l'etat du watchdog :
   ```bash
   curl http://203.0.113.50:8080/status
   curl http://203.0.113.50:8080/status/bastion
   ```
2. Verifier le cooldown et les tentatives :
   ```bash
   ssh ansible@203.0.113.50 "cat /var/log/watchdog/audit.json | python3 -m json.tool"
   ```
3. Forcer manuellement la remediation :
   ```bash
   curl -X POST http://203.0.113.50:8080/remediate/<host>
   ```
4. Si le watchdog ne repond pas, appliquer le hardening manuellement :
   ```bash
   ansible-playbook ansible/site.yml --tags hardening --limit <host> -i ansible/inventory/prod.yml --private-key ~/.ssh/id_ed25519 -u ansible -b
   ```

### Pipeline CI bloque par Trivy (CRITICAL)

1. Localiser les rapports dans les artefacts Forgejo :
   - `trivy-fs-results.json` (scan filesystem)
   - `trivy-tf-results.json` (scan configuration Terraform)
2. Analyser la criticite : conteneur image > OS package > configuration IaC
3. Corriger la source :
   - Rebuilder l'image Docker avec les patches
   - Mettre a jour le package concerne dans le playbook Ansible
   - Corriger la configuration Terraform / Ansible
4. Relancer le workflow depuis l'UI Forgejo (`Actions -> Re-run workflow`)

### Perte de connectivite reseau

1. Verifier OPNsense :
   ```bash
   curl -sk https://203.0.113.1/api/core/system/status
   # ou connexion WebUI : https://203.0.113.1
   ```
2. Verifier les VLANs sur Proxmox :
   ```bash
   pvesh get /nodes/pve/network
   ```
3. Verifier le firewall Proxmox (Datacenter -> Firewall -> Security Groups dans l'UI)
4. Verifier UFW sur la VM cible :
   ```bash
   ssh ansible@<ip> "sudo ufw status verbose"
   ```
5. Verifier les routes depuis le bastion :
   ```bash
   ssh ansible@203.0.113.5 "ip route"
   ```

### LocalStack indisponible

1. Verifier le conteneur :
   ```bash
   docker ps | grep localstack
   docker logs localstack-main --tail 50
   ```
2. Redemarrer si necessaire :
   ```bash
   cd localstack && docker compose restart
   ```
3. Verifier l'etat des services :
   ```bash
   curl -sf http://localhost:4566/_localstack/health
   ```

---

## 7. Monitoring courant

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://203.0.113.20:3000 | Voir `ansible/group_vars/all/vault.yml` |
| Forgejo | http://localhost:3000 | Compte local admin |
| Watchdog | http://203.0.113.50:8080/status | Aucun |
| Watchdog (health) | http://203.0.113.50:8080/health | Aucun |
| LocalStack | http://localhost:4566/_localstack/health | Aucun (access_key = `test`) |
| OPNsense (HA) | https://203.0.113.1 | Voir vault |
| Keycloak | https://203.0.113.20:8443 | Voir vault |

---

## 8. Checklist operationnelle hebdomadaire

- [ ] Executer `./scripts/verify.sh` : resultat `0 FAIL`
- [ ] Consulter le watchdog (`curl http://203.0.113.50:8080/status`) : aucun drift non corrige depuis plus de 24h
- [ ] LocalStack : healthcheck repond `running` sur S3/IAM/STS
- [ ] Forgejo Runner : `systemctl --user status forgejo-runner` indique `active`
- [ ] Backups S3 LocalStack : les buckets `asip-backup`, `asip-documents`, `asip-terraform-state` sont presents
- [ ] Certificats : expiration a plus de 30 jours (verifiable via Step-CA ou `openssl x509 -in <cert> -noout -dates`)
- [ ] Logs watchdog : aucune erreur repetee dans `/var/log/watchdog/watchdog.log`
- [ ] Espace disque Proxmox : `pvesh get /nodes/pve/storage/local-lvm` (usage < 80 %)
- [ ] Snapshots : verifier la presence d'un snapshot recent des VMs critiques (watchdog, routeur)

---

*Document genere le 2026-04-24. A maintenir a jour apres chaque modification majeure de l'infrastructure.*
