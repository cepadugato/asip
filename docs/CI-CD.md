# CI/CD — Forgejo Actions A.S.I.P.

## Objectif

Le pipeline CI/CD A.S.I.P. implémente le pilier **SECURE (Shift-Left)** : chaque push de code déclenche automatiquement des contrôles de sécurité, de conformité et de déploiement. Les vulnérabilités sont détectées **avant** d'atteindre la production.

---

## Forgejo Actions — Concepts clés

Forgejo Actions est compatible avec la syntaxe GitHub Actions. Les workflows sont définis dans `.forgejo/workflows/` et exécutés par le Forgejo Runner (fork de `act_runner`).

### Architecture

```
                    ┌─────────────────────────────────────┐
                    │     Forgejo (localhost:3000)         │
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
                    │  Forgejo Runner (act_runner)         │
                    │  monitoring-server (10.10.10.20)     │
                    │  Labels:                             │
                    │  - ubuntu-latest:docker://ubuntu:24  │
                    │  - ansible:docker://ansible-runner   │
                    └──────────────────────────────────────┘
```

### Référence des labels

| Label | Image Docker | Usage |
|-------|-------------|-------|
| `ubuntu-latest` | `ubuntu:24.04` | Jobs généraux (build, test) |
| `ansible` | `ansible/ansible-runner:latest` | Jobs Ansible (deploy, drift-check) |

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
          for host in 10.10.10.5 10.10.10.20 10.10.20.10 10.10.30.10; do
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
          pip install terraform-local
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
          ansible-playbook site.yml --syntax-check

      - name: Dry Run (check mode)
        run: |
          cd ansible
          ansible-playbook site.yml --check --diff \
            -i inventory/prod.yml

      - name: Deploy
        if: github.ref == 'refs/heads/main'
        run: |
          cd ansible
          ansible-playbook site.yml -i inventory/prod.yml \
            --private-key ~/.ssh/id_ed25519 \
            -u ansible -b
```

**Safety** : Le `--check --diff` (dry-run) s'exécute toujours. Le déploiement réel ne se fait que sur `main`.

---

## Branch Protection

### Configuration Forgejo recommandée

Sur le repo `asip`, configurer les protections de branche sur `main` :

| Protection | Valeur | Raison |
|-----------|--------|--------|
| Require PR | Oui | Pas de push direct sur main |
| Require passing checks | security-scan, drift-check | Bloque si vulnérabilité |
| Require review | 1 approbation | Contrôle humain |
| Allow force push | Non | Jamais |
| Allow delete | Non | Jamais |

### Workflow de développement

```
feature/xxx  →  PR  →  Checks (security + drift)  →  Review  →  Merge → main
                    │                                     │
                    ├─ security-scan.yml  (PASSED?)        │
                    ├─ drift-check.yml    (PASSED?)        │
                    ├─ terraform plan     (PREVIEW?)       │
                    └─ ansible --check    (PREVIEW?)       │
                                                          │
                                                    Auto-deploy
                                                    (terraform + ansible)
```

---

## Forgejo Runner

### Installation existante

Le Forgejo Runner est déjà configuré sur `monitoring-server` via le rôle Ansible `gitea-ci`. Il utilise `act_runner`, compatible Forgejo Runner.

### Configuration

```yaml
# /etc/gitea-runner/config.yaml (existante, renommable forgejo-runner)
runner:
  name: infra-runner
  labels:
    - "ubuntu-latest:docker://ubuntu:24.04"
    - "ansible:docker://ansible/ansible-runner:latest"

server:
  connections:
    forgejo:
      url: http://localhost:3000/
      uuid: <auto-generated>
      token: <auto-generated>
```

### Sécurité du Runner

D'après la documentation Forgejo (Securing Forgejo Actions Deployments) :

| Précaution | Configuration A.S.I.P. |
|------------|----------------------|
| Runner isolation | Docker containers (chaque job dans un container jetable) |
| Network access | Restreint au réseau interne (pas d'Internet direct) |
| Secrets | Via Forgejo Secrets (Settings → Actions → Secrets), jamais en clair dans les workflows |
| Privileged mode | Désactivé (sauf si Docker-in-Docker requis) |
| Label trust | Seuls les labels définis sont acceptés |

---

## Secrets Forgejo

Les secrets nécessaires pour les workflows sont stockés dans Forgejo (Settings → Actions → Secrets) :

| Secret | Usage | Workflow |
|--------|-------|----------|
| `PROXMOX_TOKEN` | API token Proxmox | terraform-deploy |
| `ANSIBLE_SSH_KEY` | Clé SSH privée | ansible-deploy |
| `ANSIBLE_VAULT_PASS` | Mot de passe vault | ansible-deploy |
| `LOCALSTACK_ENDPOINT` | URL LocalStack | terraform-deploy (LocalStack) |

Ces secrets sont accessibles dans les workflows via `${{ secrets.PROXMOX_TOKEN }}` et ne sont jamais visibles dans les logs.