# Script de Démonstration A.S.I.P.

Ce document décrit le scénario de démonstration pas-à-pas pour présenter les 4 piliers d'A.S.I.P. : DEPLOY, SECURE, SIMULATE, AUTONOMOUS OPS.

---

## Pré-requis de démonstration

- LocalStack démarré sur le PC hôte (`localhost:4566`)
- Forgejo accessible (`localhost:3000`)
- Infrastructure Proxmox déployée (19 VMs + 2 routeurs + 2 LXC)
- MCP Watchdog opérationnel (`192.168.100.119:8080`)
- Agent IA OpenCode connecté via MCP

---

## ACTE 1 — DEPLOY : Déploiement Zero-Touch

**Objectif** : Montrer qu'un environnement complet peut être déployé en une seule commande.

### Étape 1.1 : Déploiement complet

```bash
# Une seule commande déploie TOUT : Terraform + Ansible + Vérification
./scripts/deploy.sh all
```

**Ce qui se passe** :
1. Génération des secrets (ansible-vault)
2. Préparation des images OPNsense
3. Terraform `init` + `plan` + `apply` (19 VMs + 2 routeurs + 2 LXC)
4. Démarrage du routeur OPNsense + attente API
5. Configuration OPNsense via Ansible
6. Démarrage ordonné des VMs (AD → DHCP → PKI → Services → Collab → DMZ)
7. Attente SSH sur chaque VM
8. Ansible playbook complet (hardening + 26 rôles)
9. Vérification automatisée
10. Résumé des endpoints

**Parler pendant le déploiement** :
> "En une commande, l'ensemble de l'infrastructure est provisionné. Terraform crée les VMs, Ansible les configure, et le script vérifie que tout est opérationnel. Le tout sans intervention manuelle — c'est le Zero-Touch."

### Étape 1.2 : Vérification post-déploiement

```bash
./scripts/verify.sh
```

**Montrer** :
- Tous les services répondent (HTTP 200 sur Grafana, Keycloak, Nextcloud...)
- Les certificats TLS sont valides (délivrés par step-ca)
- AD fonctionne (LDAP bind test)
- HAProxy load balance correctement

---

## ACTE 2 — SECURE : Sécurité Shift-Left

**Objectif** : Montrer que la sécurité est intégrée dès le push, pas en production.

### Étape 2.1 : Push de code → Déclenchement automatique

```bash
# Simuler un push de configuration modifiée
git checkout -b feature/test-security
# Introduire une modification intentionnelle
echo "PermitRootLogin yes" >> ansible/roles/hardening/defaults/main.yml
git add . && git commit -m "test: intentional security drift"
git push origin feature/test-security
```

**Ce qui se passe sur Forgejo** :
1. Le workflow `security-scan.yml` se déclenche automatiquement
2. Trivy scanne le filesystem → détecte `PermitRootLogin yes` comme vulnérabilité
3. Le pipeline **échoue** avec rapport CRITICAL
4. Le merge est **bloqué**

**Parler** :
> "Le scan de sécurité est déclenché automatiquement au push. Trivy détecte la configuration vulnérable et bloque le merge. C'est le Shift-Left : on attrape le problème avant qu'il n'atteigne la production."

### Étape 2.2 : Drift Check programmé

```bash
# Consulter les résultats du dernier drift-check sur Forgejo
# Actions tab → drift-check workflow → latest run
```

**Montrer** :
- Le rapport Goss avec les checks passés/échoués
- La conformité continue (tous les jours à 04:30)

### Étape 2.3 : Hardening ANSSI

```bash
# Montrer la configuration SSH durcie sur une VM
ssh ansible@192.168.100.119 "grep -E '^(PermitRoot|Password|MaxAuth|Ciphers|MACs)' /etc/ssh/sshd_config"
```

**Montrer** :
- `PermitRootLogin no`
- `PasswordAuthentication no`
- `MaxAuthTries 3`
- Chiffrements modernes uniquement

---

## ACTE 3 — SIMULATE : Cloud Hybride Local

**Objectif** : Montrer la simulation de stockage hybride On-Prem + AWS S3 via LocalStack.

### Étape 3.1 : Démarrer LocalStack

```bash
cd localstack/
docker compose up -d

# Vérifier que LocalStack est prêt
curl -s http://localhost:4566/_localstack/health | jq .
```

**Montrer** :
- LocalStack tourne sur le PC hôte
- Les services S3 et IAM sont actifs

### Étape 3.2 : Initialisation automatique

```bash
# Les init hooks ont automatiquement créé les buckets et IAM
# Vérifier les buckets :
docker exec localstack-main aws --endpoint-url=http://localhost:4566 s3 ls
```

**Résultat attendu** :
```
2026-04-21 14:00:00 asip-backup
2026-04-21 14:00:00 asip-documents
```

**Parler** :
> "LocalStack simule les services AWS S3 et IAM en local. Les initialization hooks ont automatiquement créé les buckets et les politiques IAM au démarrage. Aucune connexion Internet nécessaire — c'est du Cloud Souverain."

### Étape 3.3 : Déploiement IaC LocalStack

```bash
# Déployer les ressources S3/IAM via Terraform (comme du vrai AWS)
cd localstack/terraform/
tflocal init
tflocal plan
tflocal apply
```

**Montrer** :
- `tflocal plan` montre exactement ce qui sera créé (comme sur AWS)
- `tflocal apply` crée les ressources dans LocalStack
- Le même code Terraform fonctionnerait sur un vrai compte AWS

### Étape 3.4 : Simulation de réplication hybride

```bash
./scripts/simulate-hybrid.sh
```

**Ce que fait le script** :
1. Crée un fichier test sur `vault-server` (on-prem)
2. Configure rclone pour pointer vers LocalStack
3. Sync le fichier vers `s3://asip-backup` (mock S3)
4. Vérifie avec `aws --endpoint-url=http://localhost:4566 s3 ls asip-backup`
5. Supprime le fichier on-prem
6. Restaure depuis LocalStack via `rclone copy`
7. Vérifie l'intégrité du fichier restauré

**Parler** :
> "Je simule ici un scénario de stockage hybride. Le fichier est d'abord créé on-premise, puis répliqué vers S3 — en réalité LocalStack, qui se comporte exactement comme AWS. En cas de perte on-prem, on restaure depuis le bucket. Tout se passe localement, sans aucun coût cloud."

### Étape 3.5 : Politiques IAM

```bash
# Montrer les utilisateurs et politiques IAM
docker exec localstack-main aws --endpoint-url=http://localhost:4566 iam list-users
docker exec localstack-main aws --endpoint-url=http://localhost:4566 iam list-policies
```

**Montrer** :
- Utilisateur `asip-backup-agent` avec accès S3 restreint
- Politique de moindre privilège (least privilege)
- Test de refus d'accès inter-bucket

---

## ACTE 4 — AUTONOMOUS OPS : Auto-remédiation

**Objectif** : Montrer que l'agent IA détecte et corrige automatiquement une dérive de configuration.

### Étape 4.1 : État initial — Tout est OK

```bash
# Vérifier le statut du watchdog
# Via le LLM (OpenCode) :
"Montre-moi l'état de l'infrastructure"
```

**Résultat LLM** :
> "L'infrastructure est saine. Les VMs et LXCs sont conformes. Aucun drift détecté."

### Étape 4.2 : Injection d'un drift (simulation d'attaque)

```bash
# Sur LXC 119 (mcp-watchdog) : modifier la config SSH (dérive volontaire)
ssh ansible@192.168.100.119 "sudo sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config"
ssh ansible@192.168.100.119 "sudo systemctl restart sshd"
```

**Parler** :
> "Je simule ici une modification non autorisée de la configuration SSH sur le mcp-watchdog (LXC 119). `PermitRootLogin` est passé de `no` à `yes`. C'est exactement le type de dérive que l'agent doit détecter et corriger."

### Étape 4.3 : Détection automatique

**Dans les 30 secondes** (webhook) ou **5 minutes max** (poller) :

```
[WATCHDOG] 14:30:15 — DRIFT DETECTED on mcp-watchdog (192.168.100.119)
[WATCHDOG]   Failed checks: 2
[WATCHDOG]   - file./etc/ssh/sshd_config.contains: expected "!/PermitRootLogin yes/"
[WATCHDOG]   - service.sshd.running: restart needed
```

### Étape 4.4 : Auto-remédiation

```
[WATCHDOG] 14:30:20 — REMEDIATION STARTED on mcp-watchdog
[WATCHDOG]   Action: ansible-playbook site.yml --tags hardening --limit mcp-watchdog
[WATCHDOG] 14:32:45 — REMEDIATION COMPLETED on mcp-watchdog (exit=0, 145s)
```

**Ce qui se passe** :
1. Le watchdog détecte le drift (SSH config modifié)
2. Il évalue la sévérité (2 checks échoués → remédiation ciblée)
3. Il exécute `ansible-playbook --tags hardening --limit bastion`
4. Ansible récrit `sshd_config` conformément au code source
5. Ansible redémarre `sshd`
6. Le prochain cycle Goss confirme la conformité restaurée

### Étape 4.5 : Vérification post-remédiation

```bash
# Vérifier que le drift est corrigé
ssh ansible@192.168.100.119 "grep PermitRootLogin /etc/ssh/sshd_config"
# Résultat attendu : PermitRootLogin no

# Via le LLM :
"Est-ce que le bastion est OK maintenant ?"
```

**Résultat LLM** :
> "Oui, le mcp-watchdog est redevenu conforme. Le drift sur la configuration SSH a été détecté à 14:30 et corrigé automatiquement en 145 secondes. PermitRootLogin est de nouveau à `no`. L'incident a été journalisé."

### Étape 4.6 : Journal d'audit

```bash
# Montrer l'historique sur le watchdog
ssh ansible@192.168.100.119 "cat /var/log/watchdog/audit.json | jq '.[-3:]'"
```

**Montrer** :
- L'événement de drift détecté
- L'action de remédiation
- La résolution confirmée

### Étape 4.7 : Scénario de récidive

```bash
# Injecter 3 drifts successifs sur le même host
for i in 1 2 3; do
  ssh ansible@192.168.100.119 "sudo sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config"
  sleep 360  # Attendre 6 min entre chaque
done
```

**Comportement attendu** :
- 1er drift → auto-remédiation
- 2e drift → auto-remédiation
- 3e drift → **Alerte P2**, arrêt de l'auto-remédiation, notification ingénieur

**Parler** :
> "Après 3 remédiations sur 24h pour le même host, le watchdog arrête l'auto-fix et alerte l'ingénieur. C'est un garde-fou essentiel : si le problème persiste, c'est qu'il y a une cause racine qu'Ansible ne peut pas résoudre seul."

---

## RÉSUMÉ — Argument de valeur

| Bénéfice | Démontré dans |
|----------|--------------|
| **Gain de temps** | Acte 1 : Déploiement complet en 1 commande vs des jours de manuel |
| **Sécurité dès le code** | Acte 2 : Vulnerability bloquée avant la production |
| **Cloud souverain** | Acte 3 : Simulation AWS sans coûts, sans données exportées |
| **Opérations autonomes** | Acte 4 : Correction automatique en < 3 min vs intervention manuelle |
| **Coût d'exploitation** | Tout est Open Source, local, sans licence cloud |
| **Conformité ANSSI** | Hardening CIS, Goss compliance, audit trail complet |