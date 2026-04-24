# CI/CD — Forgejo Actions A.S.I.P.

## Objectif

Le pipeline CI/CD A.S.I.P. implémente le pilier **SECURE (Shift-Left)** : chaque push de code déclenche automatiquement des contrôles de sécurité, de conformité et de déploiement. Les vulnérabilités sont détectées **avant** d'atteindre la production.

---

## Forgejo Actions — Concepts clés

Forgejo Actions est compatible avec la syntaxe GitHub Actions. Les workflows sont définis dans `.forgejo/workflows/` et exécutés par le Forgejo Runner (fork de `act_runner`).

### Architecture

```
                     ┌─────────────────────────────────────┐
                     │     Forgejo (localhost:3000)          │
                     │                                     │
                     │  Repo: asip                          │
                     │  Branches: main, feature/*          │
                     │                                     │
                     │  .forgejo/workflows/                 │
                     │  ├── security-scan.yml               │
                     │  ├── drift-check.yml                 │
                     │  ├── terraform-deploy.yml            │
                     │  └── ansible-deploy.yml              │
                     │                                     │
                     └──────────────┬──────────────────────┘
                                    │
                           Actions API
                                    │
                     ┌──────────────▼──────────────────────┐
                     │  Forgejo Runner v0.2.11              │
                     │  PC hôte (systemd user service)      │
                     │  Labels:                             │
                     │  - ubuntu-latest:docker://node:22-bookworm
                     │  - ansible:docker://node:22-bookworm │
                     └──────────────────────────────────────┘
```

### Référence des labels

| Label | Type | Usage |
|-------|------|-------|
| `ubuntu-latest:docker://node:22-bookworm` | Docker container | Jobs généraux (build, test, security-scan) — s'exécute dans un container Docker node:22-bookworm |
| `ansible:docker://node:22-bookworm` | Docker container | Jobs Ansible (deploy, drift-check) — Ansible est installé dans le container au runtime |

### DEFAULT_ACTIONS_URL

Par défaut : `https://data.forgejo.org`. Fournit les actions compatibles comme `actions/checkout@v4`.

---

## Workflows

### 1. security-scan.yml — Scan de vulnérabilités

**Trigger** : Push sur `main` + Schedule quotidien 03:00

```yaml
name: Security Scan

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 3 * * *'
  workflow_dispatch:

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Trivy
        run: |
          curl -fsSL https://github.com/aquasecurity/trivy/releases/download/v0.52.2/trivy_0.52.2_Linux-64bit.tar.gz -o /tmp/trivy.tar.gz
          tar -xzf /tmp/trivy.tar.gz -C /tmp
          mv /tmp/trivy /usr/local/bin/trivy
          chmod +x /usr/local/bin/trivy

      - name: Scan filesystem (configs + code)
        run: |
          trivy fs --severity CRITICAL,HIGH --format json --output trivy-fs-results.json . || true

      - name: Scan container images
        run: |
          for image in vaultwarden/server:latest keycloak/keycloak:26.0 postgres:16 nginx:1.25; do
            trivy image --severity CRITICAL,HIGH --format json \
              --output "trivy-image-$(echo $image | tr '/:' '-').json" "$image" || true
          done

      - name: Evaluate results
        run: |
          python3 -c "
          import json, glob, sys
          total_vulns = 0
          critical = 0
          for f in glob.glob('trivy-*.json'):
              try:
                  data = json.load(open(f))
                  for r in data.get('Results', []):
                      for v in r.get('Vulnerabilities', []):
                          total_vulns += 1
                          if v.get('Severity') == 'CRITICAL':
                              critical += 1
              except: pass
          print(f'Total: {total_vulns} vulns, CRITICAL: {critical}')
          if critical > 0:
              print('BLOCKING: Critical vulnerabilities found!')
              sys.exit(1)
          print('PASSED: No critical vulnerabilities')
          "

      - name: Upload scan results
        uses: actions/upload-artifact@v4
        with:
          name: trivy-results
          path: trivy-*.json
```

**Pipeline gate** : Si CRITICAL > 0, le pipeline échoue et bloque le merge.

### 2. drift-check.yml — Conformité Goss

**Trigger** : Push sur `main` + Schedule quotidien 04:30

```yaml
name: Drift Check

on:
  push:
    branches: [main]
  schedule:
    - cron: '30 4 * * *'
  workflow_dispatch:

jobs:
  drift-check:
    runs-on: ansible
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Goss
        run: |
          curl -fsSL https://github.com/goss-org/goss/releases/download/v0.4.8/goss-linux-amd64 -o /usr/local/bin/goss
          chmod +x /usr/local/bin/goss

      - name: Validate infrastructure state
        run: |
          # Récupérer les résultats Goss depuis chaque VM
          mkdir -p goss-results
          for host in 203.0.113.50 203.0.113.10 203.0.113.60; do
            scp -o StrictHostKeyChecking=no ansible@${host}:/var/log/goss/goss-results.json \
              goss-results/${host}.json 2>/dev/null || echo "{}" > goss-results/${host}.json
          done

      - name: Analyze drift
        run: |
          python3 -c "
          import json, glob, sys
          total_failed = 0
          hosts_with_drift = []
          for f in glob.glob('goss-results/*.json'):
              try:
                  data = json.load(open(f))
                  failed = data.get('summary', {}).get('failed-count', 0)
                  if failed > 0:
                      host = f.split('/')[-1].replace('.json', '')
                      hosts_with_drift.append(f'{host}: {failed} checks failed')
                      total_failed += failed
              except: pass
          if total_failed > 0:
              print(f'DRIFT DETECTED on {len(hosts_with_drift)} hosts:')
              for h in hosts_with_drift:
                  print(f'  - {h}')
              sys.exit(1)
          else:
              print('No drift detected — all hosts conformant')
          "
```

### 3. terraform-deploy.yml — Déploiement Infrastructure

**Trigger** : Push sur `main` si `terraform/**` modifié

```yaml
name: Terraform Deploy

on:
  push:
    branches: [main]
    paths: ['terraform/**', 'localstack/terraform/**']
  workflow_dispatch:

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        run: |
          curl -fsSL https://releases.hashicorp.com/terraform/1.8.0/terraform_1.8.0_linux_amd64.zip -o /tmp/terraform.zip
          unzip /tmp/terraform.zip -d /usr/local/bin/
          chmod +x /usr/local/bin/terraform
          terraform version

      - name: Terraform Init (Proxmox)
        run: |
          cd terraform
          terraform init -input=false

      - name: Terraform Plan
        run: |
          cd terraform
          terraform plan -input=false -parallelism=1 -out=tfplan

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: |
          cd terraform
          terraform apply -input=false -parallelism=1 -auto-approve tfplan

      - name: Terraform Init (LocalStack)
        run: |
          pipx install terraform-local
          cd localstack/terraform
          tflocal init -input=false

      - name: Terraform Plan (LocalStack)
        run: |
          cd localstack/terraform
          tflocal plan -out=tfplan

      - name: Terraform Apply (LocalStack)
        if: github.ref == 'refs/heads/main'
        run: |
          cd localstack/terraform
          tflocal apply -auto-approve tfplan
```

**Note** : `terraform plan` est obligatoire avant `apply`. L'apply ne s'exécute que sur la branche `main`.

### 4. ansible-deploy.yml — Déploiement Configuration

**Trigger** : Push sur `main` si `ansible/**` modifié

```yaml
name: Ansible Deploy

on:
  push:
    branches: [main]
    paths: ['ansible/**']
  workflow_dispatch:

jobs:
  ansible:
    runs-on: ansible
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Ansible collections
        run: |
          ansible-galaxy collection install community.general
          ansible-galaxy collection install ansible.posix

      - name: Syntax Check
        run: |
          cd ansible
          ANSIBLE_ROLES_PATH=roles ansible-playbook site.yml --syntax-check

      - name: Dry Run (check mode)
        run: |
          cd ansible
          ANSIBLE_ROLES_PATH=roles ansible-playbook site.yml --check --diff \
            -i inventory/prod.yml

      - name: Deploy
        if: github.ref == 'refs/heads/main'
        run: |
          cd ansible
          ANSIBLE_ROLES_PATH=roles ansible-playbook site.yml -i inventory/prod.yml \
            --private-key ~/.ssh/id_ed25519 \
            -u ansible -b
```

**Safety** : Le `--check --diff` (dry-run) s'exécute toujours. Le déploiement réel ne se fait que sur `main`.

---

## Forgejo Runner

### Architecture actuelle

Le Forgejo Runner (v0.2.11) fonctionne sur le **PC hôte** en tant que **service systemd user**. Il utilise des **containers Docker** pour l'isolation des jobs CI/CD, ce qui résout les problèmes de Docker-in-LXC.

> **Note** : Anciennement, le runner fonctionnait sur LXC 120 (192.0.2.20) en mode `host://self-hosted`. Le LXC 120 a été supprimé. Le runner utilise désormais des labels `docker://` pour exécuter chaque job dans un container Docker isolé.

### Service systemd

Le runner est géré par un service systemd user :

```ini
# /home/admin/.config/systemd/user/forgejo-runner.service
[Unit]
Description=Forgejo Runner — CI/CD for A.S.I.P.
After=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/forgejo-runner daemon --config /opt/asip/.runner-home/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
```

**Commandes de gestion** :

```bash
# Démarrer le runner
systemctl --user start forgejo-runner.service

# Vérifier le statut
systemctl --user status forgejo-runner.service

# Voir les logs
journalctl --user -u forgejo-runner.service -f

# Arrêter le runner
systemctl --user stop forgejo-runner.service
```

### Configuration

```yaml
# /opt/asip/.runner-home/config.yaml
runner:
  name: infra-runner
  labels:
    - "ubuntu-latest:docker://node:22-bookworm"
    - "ansible:docker://node:22-bookworm"

container:
  network: host
  valid_volumes: []

server:
  url: http://localhost:3000/
  uuid: <auto-generated>
  token: <auto-generated>
```

### Sécurité du Runner

D'après la documentation Forgejo (Securing Forgejo Actions Deployments) :

| Précaution | Configuration A.S.I.P. |
|------------|----------------------|
| Runner isolation | **Docker container isolation** — chaque job s'exécute dans un container Docker `node:22-bookworm` éphémère |
| Network access | Mode `host` (accès au réseau local pour Ansible SSH, LocalStack, etc.) |
| Secrets | Via Forgejo Secrets (Settings → Actions → Secrets), jamais en clair dans les workflows |
| Privileged mode | Non (Docker sans `--privileged`) |
| Label trust | Seuls les labels définis sont acceptés |
| Service management | systemd user service (`systemctl --user`) — pas besoin de `sudo` |

---

## Secrets Forgejo

Les secrets nécessaires pour les workflows sont stockés dans Forgejo (Settings → Actions → Secrets) :

| Secret | Usage | Workflow |
|--------|-------|----------|
| `PROXMOX_TOKEN` | API token Proxmox | terraform-deploy |
| `ANSIBLE_SSH_KEY` | Clé SSH privée | ansible-deploy |
| `ANSIBLE_VAULT_PASS` | Mot de passe vault | ansible-deploy |
| `AWS_ENDPOINT_URL` | URL LocalStack | terraform-deploy (LocalStack) |

Ces secrets sont accessibles dans les workflows via `${{ secrets.PROXMOX_TOKEN }}` et ne sont jamais visibles dans les logs.

---

## Pipeline Status

Les 4 workflows sont actuellement **tous verts** (passing) :

| Workflow | Statut | Trigger |
|----------|--------|---------|
| `security-scan.yml` | ✅ PASSING | Push sur `main` + schedule 03:00 |
| `drift-check.yml` | ✅ PASSING | Push sur `main` + schedule 04:30 |
| `terraform-deploy.yml` | ✅ PASSING | Push sur `main` si `terraform/**` modifié |
| `ansible-deploy.yml` | ✅ PASSING | Push sur `main` si `ansible/**` modifié |

---

## Découvertes clés (Runbook)

Les problèmes suivants ont été résolus lors de la mise en service du pipeline :

| Probleme | Solution | Detail |
|----------|----------|--------|
| Installation de `tflocal` | `pipx install terraform-local` | `pip3 install` ne fonctionne pas correctement dans le container CI ; `pipx` est le paquet officiellement recommande |
| Endpoint LocalStack dans Terraform | `AWS_ENDPOINT_URL` | Variable d'environnement standard AWS utilisee par `tflocal` ; `LOCALSTACK_ENDPOINT` n'est pas reconnue par le provider AWS |
| Roles Ansible introuvables en CI | `ANSIBLE_ROLES_PATH=roles` | Ansible ne trouve pas les roles locaux sans cette variable d'environnement ; a definir sur chaque appel `ansible-playbook` |
| `aws_caller_identity` data source en LocalStack | `SERVICES=s3,iam,sts` | LocalStack doit inclure le service `sts` pour que la data source `aws_caller_identity` fonctionne (sinon erreur 500) |

---

## Branch Protection

### Configuration requise sur `main`

Dans Forgejo (Settings -> Repository -> Settings -> Branch Protection), configurer :

| Protection | Valeur | Justification |
|-----------|--------|--------------|
| Enable Branch Protection | Oui | Empeche les pushs directs |
| Protected File Patterns | `terraform/**`, `ansible/**`, `.forgejo/workflows/**`, `mcp-agent/**` | Fichiers critiques immuables sans PR |
| Required Approvals | 1 | Revue humaine obligatoire |
| Dismiss stale approvals | Oui | Nouveau commit = nouvelle revue |
| Require signed commits | Oui | Tracabilite GPG |
| Block merge on failing checks | Oui | Bloque si CI echoue |
| Status Checks | security-scan, drift-check, terraform-plan, ansible-check | Seuls les checks requis passent |
| Allow force push | Non | Jamais de force push sur prod |
| Allow deletions | Non | Jamais de suppression de branche |

### Workflow de developpement

```
feature/xxx -> PR vers main -> CI checks -> Review -> Merge -> CD
```

| Etape | Outil | Validation |
|-------|-------|------------|
| 1. Feature branch | git checkout -b feature/xxx | Prefixe conventionnel |
| 2. Commit | git commit -m "type: description" | Conventionnal commits |
| 3. Push | git push origin feature/xxx | Declenche CI |
| 4. PR | Forgejo UI | Template PR obligatoire |
| 5. CI | Forgejo Actions | 4 workflows doivent passer |
| 6. Review | Approbateur | Au moins 1 approve |
| 7. Merge | Squash & merge | Historique lineaire |
| 8. CD | Forgejo Actions auto | Deploy sur main |

### Checklist PR Template

Creer un fichier `.gitea/PULL_REQUEST_TEMPLATE.md` avec :

```markdown
## Description
[Description courte des changements]

## Type de changement
- [ ] Bug fix (correction non-breaking)
- [ ] Feature (ajout non-breaking)
- [ ] Breaking change
- [ ] Documentation

## Checklist
- [ ] Les tests CI passent (security-scan, drift-check)
- [ ] Terraform plan a ete revu
- [ ] Ansible --check a ete execute
- [ ] La documentation est a jour
- [ ] Les secrets ne sont pas en clair
- [ ] Le code suit les standards ANSSI

## Tests
[Comment a ete teste ce changement]
```

## Impact

- Securite : empeche le push direct de code non revu
- Tracabilite : chaque changement est associe a une PR
- Qualite : CI bloque les merges si checks echouent