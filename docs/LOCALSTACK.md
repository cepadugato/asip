# LocalStack — Simulation Cloud Hybride A.S.I.P.

## Objectif

LocalStack fournit une **simulation fidèle des services AWS** (S3 + IAM) fonctionnant entièrement en local sur le PC hôte. Dans A.S.I.P., il sert à :

1. Simuler un stockage hybride On-Premise + AWS S3
2. Tester les politiques IAM (moindre privilège) sans compte AWS
3. Valider les configurations Terraform AWS avant un éventuel déploiement cloud réel
4. Garantir la **souveraineté** : aucune donnée ne quitte le réseau local

---

## Installation

### Docker Compose

Le fichier `localstack/docker-compose.yml` configure LocalStack avec S3 et IAM uniquement :

```yaml
services:
  localstack:
    container_name: localstack-main
    image: localstack/localstack:3
    ports:
      - "127.0.0.1:4566:4566"            # LocalStack Gateway
    environment:
      - SERVICES=s3,iam
      - AWS_DEFAULT_REGION=eu-west-1
      - PERSISTENCE=1                      # Persistance entre redémarrages
      - DEBUG=0
    volumes:
      - ./volume:/var/lib/localstack       # Persistance des données
      - ./init:/etc/localstack/init/ready.d  # Initialization hooks
      - /var/run/docker.sock:/var/run/docker.sock
```

### Démarrage

```bash
cd localstack/
docker compose up -d
```

### Vérification

```bash
# Santé de LocalStack
curl -s http://localhost:4566/_localstack/health | jq .

# État des initialization hooks
curl -s http://localhost:4566/_localstack/init | jq .
```

### Arrêt

```bash
docker compose down
# Les données persistent dans ./volume/ (PERSISTENCE=1)
```

---

## Initialization Hooks

LocalStack exécute automatiquement les scripts dans `/etc/localstack/init/ready.d/` une fois prêt. Ces scripts sont montés depuis `./init/`.

### 01-create-buckets.sh

```bash
#!/bin/bash
# Crée les buckets S3 avec configuration de production-like

# Bucket de sauvegarde
awslocal s3 mb s3://asip-backup
awslocal s3api put-bucket-versioning \
  --bucket asip-backup \
  --versioning-configuration Status=Enabled
awslocal s3api put-bucket-lifecycle-configuration \
  --bucket asip-backup \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "ExpireAfter30Days",
      "Status": "Enabled",
      "Prefix": "",
      "Expiration": { "Days": 30 }
    }]
  }'

# Bucket de documents
awslocal s3 mb s3://asip-documents
awslocal s3api put-bucket-versioning \
  --bucket asip-documents \
  --versioning-configuration Status=Enabled
awslocal s3api put-bucket-lifecycle-configuration \
  --bucket asip-documents \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "ExpireAfter90Days",
      "Status": "Enabled",
      "Prefix": "",
      "Expiration": { "Days": 90 }
    }]
  }'

echo "Buckets S3 created successfully"
```

### 02-create-iam.sh

```bash
#!/bin/bash
# Crée les utilisateurs et politiques IAM

# Utilisateur de sauvegarde
awslocal iam create-user --user-name asip-backup-agent
awslocal iam create-access-key --user-name asip-backup-agent

# Politique de sauvegarde (accès complet sur asip-backup uniquement)
awslocal iam put-user-policy \
  --user-name asip-backup-agent \
  --policy-name AsipBackupPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": [
        "arn:aws:s3:::asip-backup",
        "arn:aws:s3:::asip-backup/*"
      ]
    }]
  }'

# Utilisateur de synchronisation documents
awslocal iam create-user --user-name asip-docs-sync
awslocal iam create-access-key --user-name asip-docs-sync
awslocal iam put-user-policy \
  --user-name asip-docs-sync \
  --policy-name AsipDocsSyncPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
        "Resource": [
          "arn:aws:s3:::asip-documents",
          "arn:aws:s3:::asip-documents/*"
        ]
      }
    ]
  }'

# Rôle cross-account pour scénarios avancés
awslocal iam create-role \
  --role-name asip-backup-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::000000000000:root"},
      "Action": "sts:AssumeRole"
    }]
  }'
awslocal iam put-role-policy \
  --role-name asip-backup-role \
  --policy-name AsipBackupRolePolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::asip-backup",
        "arn:aws:s3:::asip-backup/*"
      ]
    }]
  }'

echo "IAM users and policies created successfully"
```

---

## Terraform LocalStack

### Provider Configuration

Le provider AWS est configuré pour pointer vers LocalStack. Deux approches possibles :

#### Approche 1 : `tflocal` (recommandé)

```bash
pip install terraform-local
tflocal init
tflocal plan
tflocal apply
```

`tflocal` génère automatiquement un override qui configure tous les endpoints vers `localhost:4566`.

#### Approche 2 : Configuration manuelle

```hcl
provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "eu-west-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true

  endpoints {
    s3  = "http://localhost:4566"
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}
```

### Détection LocalStack

```hcl
# Heuristique pour détecter si on tourne sur LocalStack
data "aws_caller_identity" "current" {}

output "is_localstack" {
  value = data.aws_caller_identity.current.id == "000000000000"
}
```

### Ressources Terraform

Le fichier `localstack/terraform/main.tf` déclare les mêmes ressources que les init hooks, mais de manière déclarative et versionnée. Celles-ci peuvent être utilisées à la place des hooks, ou en complément pour des scénarios plus avancés.

---

## Utilisation avec rclone

### Configuration rclone

Sur les VMs (vault-server, collab-server), le rôle Ansible `hybrid-storage` configure rclone :

```ini
[asip-s3]
type = s3
provider = Other
env_auth = false
access_key_id = test
secret_access_key = test
endpoint = http://localhost:4566
force_path_style = true
```

### Commandes utiles

```bash
# Lister les buckets
rclone lsd asip-s3:

# Copier un fichier vers LocalStack
rclone copy /var/lib/vaultwarden/backup.db asip-s3:asip-backup/vaultwarden/

# Synchroniser un répertoire
rclone sync /var/www/nextcloud/data/ asip-s3:asip-documents/nextcloud/ --verbose

# Restaurer depuis LocalStack
rclone copy asip-s3:asip-backup/vaultwarden/backup.db /var/lib/vaultwarden/
```

### Cron de synchronisation

```cron
# Sauvegarde quotidienne vaultwarden vers LocalStack
0 2 * * * rclone copy /var/lib/vaultwarden/ asip-s3:asip-backup/vaultwarden/ --verbose >> /var/log/rclone-backup.log 2>&1

# Synchronisation continue Nextcloud
*/15 * * * * rclone sync /var/www/nextcloud/data/ asip-s3:asip-documents/nextcloud/ >> /var/log/rclone-sync.log 2>&1
```

---

## Sécurité LocalStack

### Credentials mock

| Variable | Valeur | Raison |
|----------|--------|--------|
| `AWS_ACCESS_KEY_ID` | `test` | Mock LocalStack, pas de credentials réels |
| `AWS_SECRET_ACCESS_KEY` | `test` | Mock LocalStack |
| `AWS_DEFAULT_REGION` | `eu-west-1` | LocalStack accepte toute région |

### Isolation réseau

LocalStack est accessible uniquement sur `127.0.0.1:4566` (localhost). Les VMs y accèdent via le routeur OPNsense si une route est configurée, ou via le réseau local du PC hôte.

### Limites connues

| Limite | Détail |
|--------|--------|
| Pas de réel S3 | Les données sont stockées dans le volume Docker local |
| Pas de IAM enforcement | LocalStack n'enforce pas les politiques IAM par défaut (Pro feature) |
| Persistance | Activée via `PERSISTENCE=1`, mais les données sont éphémères par conception |
| S3 Path Style | Nécessaire (`s3_use_path_style = true`) car DNS virtuel non résolvable |

---

## Montée vers le cloud réel

L'intérêt de LocalStack est de permettre un développement et des tests locaux. Quand le passage au cloud est nécessaire :

1. Les mêmes fichiers Terraform fonctionnent sur un vrai compte AWS
2. Il suffit de retirer la configuration `endpoints` du provider
3. De remplacer les credentials mock par de vrais credentials
4. Les scripts rclone fonctionnent avec le vrai endpoint S3

C'est la **promesse du Cloud Souverain** : développer en local, déployer où l'on veut.