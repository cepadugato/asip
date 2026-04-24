# Guide de Dépanage A.S.I.P.

## Diagnostic rapide (arbre décision)

```
Pipeline CI échoue
  ├── security-scan.yml → Voir "Trivy CRITICAL"
  ├── terraform-deploy.yml → Voir "Terraform errors"
  │   ├── terraform init bloque → Voir "Backend HTTP Forgejo"
  │   └── task still in progress → Voir "Lock error sur Proxmox"
  ├── ansible-deploy.yml → Voir "Ansible unreachable"
  │   └── UNREACHABLE! → Voir "Unreachable host"
  │   └── Vault password incorrect → Voir "Vault password incorrect"
  └── drift-check.yml → Voir "Goss validation failed"

VM ne répond pas
  ├── API watchdog down → Voir "Watchdog API not responding"
  ├── SSH impossible → Voir "Ansible unreachable"
  └── Cloud-Init raté → Voir "Cloud-Init non appliqué"

Terraform bloque sur Proxmox
  ├── 401 Unauthorized → Voir "API 401"
  ├── CT is locked → Voir "Lock error sur Proxmox"
  └── Clonage timeout → Voir "Clonage timeout"

LocalStack / S3
  ├── curl localhost:4566 refused → Voir "LocalStack not ready"
  └── rclone signature error → Voir "Signature error (rclone)"

Forgejo Actions
  └── Job reste en pending → Voir "Runner not active"
  └── aws/jq introuvable dans le job → Voir "Missing tools in container"

Watchdog agite
  └── Remediation en boucle sur le meme host → Voir "Boucle de remediation"
```

---

## Erreurs par composant

### Terraform

#### Lock error sur Proxmox

**Symptome**
```
Error: task still in progress
Error: CT is locked (backup)
Error: resource temporarily unavailable
```
Terraform s'arrete ou echoue de maniere intermittente sur des operations `proxmox_virtual_environment_vm`.

**Diagnostic**
1. Verifier si un backup ou un snapshot Proxmox est en cours sur le node cible :
   ```bash
   ssh root@pve "qm list | grep -i lock"
   ssh root@pve "pvesh get /cluster/tasks --output-format json | jq '.[] | select(.status | contains(\"running\"))'"
   ```
2. Verifier le parallelisme actuel :
   ```bash
   ps aux | grep "terraform apply" | grep -o "parallelism=[0-9]*"
   ```

**Cause**
Le parallelisme par defaut de Terraform est `10`. Proxmox (bpg/provider ~> 0.61) verrouille les VM/CT pendant les operations (clone, resize, boot). Lorsque Terraform tente d'appliquer plusieurs ressources simultanement sur le meme node, il entre en conflit avec le verrouillage interne de Proxmox. Un backup `vzdump` declenche en arriere-plan aggrave le probleme.

**Solution**
Toujours forcer le parallelisme a `1` lors des apply et des plan sur Proxmox :
```bash
terraform plan -parallelism=1 -out=tfplan
terraform apply -parallelism=1 -auto-approve tfplan
```
Pour attendre la fin d'un backup en cours avant de relancer :
```bash
ssh root@pve "pvesh get /cluster/tasks" | grep vzdump
```

**Prevention**
- Integrer `-parallelism=1` dans tous les scripts de deploiement (`deploy.sh`, CI/CD).
- Ne pas declencher de backup Proxmox pendant un `terraform apply`.
- Configurer les fenetres de maintenance Terraform en dehors des horaires de backup automatiques.

---

#### Backend HTTP Forgejo

**Symptome**
```
Error: HTTP remote state endpoint invalid
Error: Unexpected HTTP response code 404
Error: Failed to get state: HTTP error: 404 Not Found
```
`terraform init` echoue specifiquement sur le backend HTTP.

**Diagnostic**
1. Verifier la declaration du backend dans `terraform/main.tf` :
   ```bash
   cat terraform/main.tf | grep -A 5 "backend \"http\""
   ```
   Le backend pointe sur `http://localhost:3000/api/state/asip`.
2. Tester si Forgejo repond sur l'URL de state :
   ```bash
   curl -sf http://localhost:3000/api/state/asip || echo "Forgejo state endpoint unreachable"
   ```
3. Verifier si on est en CI (ou hote sans Forgejo) :
   ```bash
   echo "${GITHUB_ACTIONS}${CI}"
   ```

**Cause**
Forgejo ne fournit pas nativement un endpoint de stockage d'etat Terraform HTTP. Le bloc `backend "http"` dans `terraform/main.tf` est configure pour pointer vers une API qui n'existe pas ou n'est pas encore implementee dans Forgejo. En local, cela peut fonctionner si un proxy/script intermediaire est present ; en CI, l'endpoint est absent.

**Solution**
En CI/CD, desactiver le backend HTTP et utiliser un backend local ou S3 :
```bash
cd terraform
terraform init -backend=false
terraform plan -parallelism=1 -out=tfplan
```

**Prevention**
- Separer la configuration backend par environnement :
  - `dev` : backend local (`terraform { backend "local" { path = "terraform.tfstate" } }`).
  - `ci` : init avec `-backend=false`.
  - `prod` : backend S3 compatible (LocalStack en dev/test, AWS S3 en prod).
- Documenter le comportement du backend HTTP dans le README Terraform.

---

#### Cloud-Init non applique

**Symptome**
- La VM boote mais n'a pas d'IP reseau (ping impossible).
- Le hostname reste celui du template (`ubuntu-template` au lieu de `mcp-watchdog`).
- `cloud-init status` retourne `not run` ou `disabled`.

**Diagnostic**
1. Verifier la console serie de la VM dans Proxmox :
   ```bash
   qm console <vmid>
   ```
2. Verifier si le fichier `user-data` est bien attache :
   ```bash
   ssh root@pve "cat /var/lib/vz/snippets/user-data-*.yml"
   ```
3. Verifier la presence de `serial_device` dans le Terraform state :
   ```bash
   terraform show | grep -A 2 serial_device
   ```

**Cause**
Les templates Debian/Ubuntu sur Proxmox necessitent un peripherique serie (`serial0`) pour que l'agent cloud-init puisse recevoir les donnees de configuration. Sans `serial_device { device = "socket" }`, cloud-init ne detecte pas la source de configuration et ignore le disque CDROM/cloud-init.

**Solution**
S'assurer que le bloc `serial_device` est present dans `terraform/main.tf` :
```hcl
resource "proxmox_virtual_environment_vm" "mcp_watchdog" {
  # ...
  serial_device {
    device = "socket"
  }
  # ...
}
```
Appliquer a nouveau :
```bash
terraform apply -parallelism=1 -target=proxmox_virtual_environment_vm.mcp_watchdog
```

**Prevention**
- Ajouter `serial_device { device = "socket" }` comme convention obligatoire dans tous les templates Terraform pour VM Debian/Ubuntu.
- Tester le boot de la VM immediatement apres le clone pour valider Cloud-Init.

---

### Ansible

#### Unreachable host

**Symptome**
```
UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh", "unreachable": true}
```
Ansible s'arrete a la premiere tache sur le ou les hotes cibles.

**Diagnostic**
1. Verifier la connectivite reseau de base :
   ```bash
   ping <host_ip>
   ```
2. Verifier l'acces SSH manuellement :
   ```bash
   ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i ~/.ssh/id_ed25519 ansible@<host_ip> "echo OK"
   ```
3. Verifier la presence de la cle privee :
   ```bash
   ls -la ~/.ssh/id_ed25519
   ssh-add -l | grep id_ed25519
   ```
4. Verifier l'etat du pare-feu sur l'hote cible :
   ```bash
   ssh root@<host_ip> "ufw status verbose"
   ```
5. Verifier si la VM/LXC a fini de booter (Cloud-Init) :
   ```bash
   ssh root@<host_ip> "cloud-init status --wait"
   ```

**Cause**
- La VM/LXC n'a pas encore termine son boot et Cloud-Init (pas d'IP, SSH pas encore actif). `deploy.sh` attend 60 retries x 5s = 5 minutes, mais l'initialisation peut prendre plus longtemps sur un clone complet.
- La cle SSH `~/.ssh/id_ed25519` est absente ou non deployee sur l'hote.
- Le pare-feu UFW ou Proxmox bloque le port 22 depuis la source.
- Le user `ansible` n'existe pas (Cloud-Init n'a pas injecte la cle publique).

**Solution**
- Attendre le boot complet de la VM avant de lancer Ansible. Le script `deploy.sh` le fait, mais en cas d'echec, attendre 30 secondes supplementaires et relancer :
  ```bash
  sleep 30
  ansible-playbook -i ansible/inventory/prod.yml ansible/site.yml --private-key ~/.ssh/id_ed25519 -u ansible -b
  ```
- Si la cle est manquante, la generer/deployer :
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
  ```
- Ouvrir le port SSH sur UFW si necessaire :
  ```bash
  ufw allow from 203.0.113.0/24 to any port 22 proto tcp
  ```

**Prevention**
- Toujours valider le boot Cloud-Init avant de lancer Ansible (`deploy.sh` step 4).
- Stocker la cle SSH dans les secrets Forgejo (`ANSIBLE_SSH_KEY`) pour la CI.
- S'assurer que le template source a le user `ansible` cree avec la cle publique admin.

---

#### Vault password incorrect

**Symptome**
```
ERROR! Decryption failed on ansible/.../vars/main.yml
fatal: [host]: FAILED! => {"msg": "The vault password file /path/.vault_pass was not found"}
```

**Diagnostic**
1. Verifier l'existence du fichier de mot de passe vault :
   ```bash
   ls -la ~/.vault_pass
   ```
2. Verifier la configuration Ansible :
   ```bash
   cat ansible/ansible.cfg | grep vault_password_file
   ```
3. Verifier le chemin dans la config du watchdog :
   ```bash
   cat mcp-agent/config.yaml | grep vault
   ```

**Cause**
Le fichier `~/.vault_pass` n'existe pas, est vide, ou ne contient pas le bon mot de passe. Les variables chiffrees (mots de passe, tokens) ne peuvent pas etre dechiffrees.

**Solution**
- Creer le fichier avec le mot de passe exact :
  ```bash
  echo "<vault_password>" > ~/.vault_pass
  chmod 600 ~/.vault_pass
  ```
- En CI/CD, injecter le secret `ANSIBLE_VAULT_PASS` dans une variable d'environnement ou un fichier temporaire :
  ```bash
  echo "$ANSIBLE_VAULT_PASS" > /tmp/.vault_pass
  ansible-playbook ... --vault-password-file /tmp/.vault_pass
  rm -f /tmp/.vault_pass
  ```

**Prevention**
- Documenter la creation du fichier `~/.vault_pass` dans le setup post-installation.
- Ne jamais versionner le fichier de mot de passe.
- Utiliser les secrets Forgejo pour injecter le mot de passe en CI.

---

### Proxmox

#### API 401

**Symptome**
```bash
curl -k "https://192.0.2.254:8006/api2/json/nodes"
```
Retourne `401 No ticket` ou `401 Unauthorized`.
Terraform retourne `401 Unauthorized: user name or password verification failed`.

**Diagnostic**
1. Tester avec les credentials corrects :
   ```bash
   curl -k "https://192.0.2.254:8006/api2/json/nodes" \
     -H "Authorization: PVEAPIToken root@pam!terraform=<TOKEN>"
   ```
2. Verifier les variables d'environnement ou le provider Terraform :
   ```bash
   env | grep PROXMOX
   grep -A 5 "provider \"proxmox\"" terraform/main.tf
   ```

**Cause**
Le provider Terraform `bpg/proxmox` et les appels API direct (`verify.sh`, `deploy.sh`) utilisent l'authentification par **API Token** (`PVEAPIToken`), PAS l'authentification par mot de passe classique. Si on passe `root@pam` + `password`, Proxmox renvoie 401. De meme, si le token est invalide, expire, ou s'il manque le `!terraform` dans le header.

**Solution**
- Utiliser systématiquement le format API token dans le header HTTP :
  ```
  Authorization: PVEAPIToken root@pam!terraform=<token_value>
  ```
- Dans Terraform, utiliser `api_token` (variable `var.proxmox_token`) et non `password` :
  ```hcl
  provider "proxmox" {
    endpoint  = var.proxmox_endpoint
    api_token = var.proxmox_token
    insecure  = var.proxmox_insecure
  }
  ```
- Generer un nouveau token si perdu (via l'UI Proxmox : Datacenter -> API Tokens).

**Prevention**
- Documenter dans `opencode.json` et les variables d'environnement que `PROXMOX_TOKEN_NAME` et `PROXMOX_TOKEN_VALUE` sont obligatoires.
- Ne jamais utiliser `PROXMOX_PASSWORD` avec ce provider.

---

#### Clonage timeout

**Symptome**
```
proxmox_virtual_environment_vm.mcp_watchdog: Still creating... [3m0s elapsed]
Error: timeout while waiting for VM clone to complete
```

**Diagnostic**
1. Verifier les taches Proxmox en cours :
   ```bash
   ssh root@pve "pvesh get /cluster/tasks"
   ```
2. Verifier l'espace disque sur le stockage cible :
   ```bash
   ssh root@pve "pvesm status"
   ```
3. Verifier les logs Terraform avec `TF_LOG=DEBUG`.

**Cause**
- Le stockage source ou cible est surcharge (I/O eleve).
- Un backup `vzdump` est en cours sur le meme pool de stockage.
- Le timeout Terraform (`migrate = 180`, `shutdown = 300`) est insuffisant pour un clone `full = true` de 32G sur un stockage mecanique.

**Solution**
- Augmenter les timeouts dans Terraform si le stockage est lent :
  ```hcl
  timeout {
    migrate  = 300
    shutdown = 600
  }
  ```
- Relancer le clone en dehors des heures de backup.

**Prevention**
- Utiliser `full = false` (linked clone) si le template et la cible sont sur le meme stockage local, ou si l'espace disque est limite (attention aux implications de performance).
- Programmer les clones Terraform en dehors des fenetres de backup.

---

### LocalStack

#### Not ready

**Symptome**
```bash
curl -sf http://localhost:4566/_localstack/health
```
Retourne `Connection refused`. `deploy.sh` affiche `LocalStack not ready after 2.5 minutes`.

**Diagnostic**
1. Verifier l'etat du container Docker :
   ```bash
   docker ps | grep localstack-main
   docker inspect localstack-main --format='{{.State.Status}}'
   ```
2. Consulter les logs du container :
   ```bash
   docker logs localstack-main --tail 50
   ```
3. Verifier le healthcheck Docker :
   ```bash
   docker inspect localstack-main --format='{{.State.Health}}'
   ```
4. Verifier que le port n'est pas conflit :
   ```bash
   sudo ss -tlnp | grep 4566
   ```

**Cause**
LocalStack demarre en `30-60s` minimum. Sur un PC hote avec peu de ressources, Docker peut mettre plus de temps a initialiser les services S3/IAM/STS. Le timeout de `2.5 minutes` (30 retries x 5s) peut etre insuffisant si le container est en `restart unless-stopped` apres un crash.

**Solution**
- Attendre manuellement et verifier le healthcheck :
  ```bash
  until curl -sf http://localhost:4566/_localstack/health; do
    echo "Waiting for LocalStack..."
    sleep 5
  done
  ```
- Redemarrer le container si necessaire :
  ```bash
  cd localstack && docker compose down && docker compose up -d
  docker logs -f localstack-main
  ```

**Prevention**
- Augmenter les retries dans `deploy.sh` si l'hote est lent (passer a 60 x 5s).
- S'assurer que Docker a assez de RAM/CPU alloues (minimum 2 CPU, 4G RAM recommande).
- Utiliser `PERSISTENCE=1` pour eviter les re-creations couteuses des buckets a chaque redemarrage.

---

#### Signature error (rclone)

**Symptome**
```bash
rclone ls localstack:asip-backup
```
Retourne :
```
SignatureDoesNotMatch: The request signature we calculated does not match the signature you provided
```

**Diagnostic**
1. Verifier la configuration rclone :
   ```bash
   rclone config show localstack
   ```
2. Tester avec awslocal/AWS CLI :
   ```bash
   aws --endpoint-url=http://localhost:4566 s3 ls
   ```
3. Verifier les credentials utilises :
   ```bash
   cat ~/.config/rclone/rclone.conf | grep -A 5 "localstack"
   ```

**Cause**
LocalStack avec le provider AWS S3 mock necessite des parametres specifiques pour la signature V4. `force_path_style=true` est obligatoire. La region doit correspondre (`eu-west-1`). Les credentials LocalStack par defaut sont `test` / `test`. Si `force_path_style` est absent, rclone tente de signer avec un style d'URL virtual-hosted qui ne correspond pas a l'endpoint LocalStack.

**Solution**
Creer le remote rclone avec les parametres exacts :
```bash
rclone config create localstack \
  s3 \
  provider=Other \
  env_auth=false \
  access_key_id=test \
  secret_access_key=test \
  endpoint="http://localhost:4566" \
  force_path_style=true \
  region=eu-west-1 \
  no_check_bucket=true
```

**Prevention**
- Versionner un template `rclone.conf` dans le projet (ou dans Ansible templates `rclone.conf.j2`) avec les parametres corrects.
- Tester `rclone ls` systematiquement apres le demarrage de LocalStack dans `verify.sh`.

---

### MCP Watchdog

#### API not responding

**Symptome**
```bash
curl -sf http://203.0.113.50:8080/status
```
Timeout. `verify.sh` affiche `Watchdog API not responding`.

**Diagnostic**
1. Verifier l'etat du service systemd sur le host watchdog :
   ```bash
   ssh -o StrictHostKeyChecking=no root@203.0.113.50 "systemctl status mcp-watchdog"
   ```
2. Verifier les logs du watchdog :
   ```bash
   ssh root@203.0.113.50 "journalctl -u mcp-watchdog -n 50 --no-pager"
   ssh root@203.0.113.50 "cat /var/log/watchdog/audit.json | tail -n 20"
   ```
3. Verifier la configuration :
   ```bash
   ssh root@203.0.113.50 "cat /opt/asip/mcp-agent/config.yaml"
   ```
4. Verifier le pare-feu UFW :
   ```bash
   ssh root@203.0.113.50 "ufw status verbose | grep 8080"
   ```
5. Verifier que le port est bien en ecoute :
   ```bash
   ssh root@203.0.113.50 "ss -tlnp | grep 8080"
   ```

**Cause**
- Le service systemd `mcp-watchdog` n'est pas demarre (dependance Python manquante, erreur au boot).
- L'environnement virtuel Python n'a pas les dependances (`requirements.txt` non installe).
- UFW bloque le port 8080 sur l'interface reseau.
- La config `config.yaml` pointe sur un mauvais `inventory` ou `ansible_playbook`, ce qui fait crasher le worker au demarrage.

**Solution**
- Redemarrer le service :
  ```bash
  ssh root@203.0.113.50 "systemctl restart mcp-watchdog && sleep 2 && systemctl status mcp-watchdog"
  ```
- Si le service est `failed`, inspecter l'erreur Python dans `journalctl` :
  ```bash
  ssh root@203.0.113.50 "journalctl -u mcp-watchdog -f"
  ```
- Si UFW bloque, ouvrir explicitement (deja fait par le role Ansible mais a verifier) :
  ```bash
  ufw allow from 203.0.113.0/24 to any port 8080 proto tcp
  ```

**Prevention**
- Le role Ansible `mcp-watchdog` deploye une regle UFW et attend que le port soit ouvert (`wait_for: port=8080`). S'assurer que le role s'execute sans erreur.
- Surveiller le service avec systemd (`Restart=always`).

---

#### Boucle de remediation

**Symptome**
```bash
curl http://203.0.113.50:8080/status
```
Montre un host passant en `DRIFT`, puis `OK`, puis `DRIFT` a nouveau dans un intervalle court. L'audit log (`/var/log/watchdog/audit.json`) montre 3 ou plus remediations sur le meme host en 24h.

**Diagnostic**
1. Lire l'audit log :
   ```bash
   ssh root@203.0.113.50 "cat /var/log/watchdog/audit.json | python3 -m json.tool | grep remediation"
   ```
2. Verifier la config du rate limiter :
   ```bash
   ssh root@203.0.113.50 "grep max_remediations mcp-agent/config.yaml"
   ```
3. Verifier les causes persistantes sur l'hote cible :
   ```bash
   ssh root@<host_cible> "df -h"        # disque plein ?
   ssh root@<host_cible> "dmesg | tail" # erreurs kernel ?
   ssh root@<host_cible> "goss -g /etc/goss/goss.yaml validate --format json" | python3 -m json.tool | grep FAIL
   ```

**Cause**
Un probleme de fond persiste sur l'hote cible (disque plein, package corrompu, dependance circulaire dans les regles Goss, race condition entre le remplacement de fichier et le redemarrage de service). Le watchdog detecte la derive, Ansible remidie temporairement, mais la derive revient immediatement (ex: un service qui crash au boot, un fichier remodifie par un autre processus).

**Solution**
- Le watchdog s'arrete automatiquement apres `max_remediations_24h = 3` (defini dans `config.yaml`).
- Investigation manuelle obligatoire :
  ```bash
  ssh root@<host_cible>
  # Identifier la cause racine : logs applicatifs, disque, conflits de packages
  journalctl -xe
  apt list --upgradable
  ```
- Desactiver temporairement l'auto-remediation si une intervention manuelle est en cours :
  ```bash
  ssh root@203.0.113.50 "systemctl stop mcp-watchdog-poll.timer"
  ```
- Corriger la derive a la source (ex: augmenter le disque, fixer le package, ajuster Goss pour ignorer une variante acceptable).

**Prevention**
- Configurer `max_remediations_24h` a une valeur basse (3) pour eviter les boucles infinies.
- Ajouter une alerte (webhook ou log externe) lorsqu'un host atteint la limite.
- Monitorer les metriques systeme (disque, memoire) en amont pour eviter les derives recurrentes.

---

### Forgejo CI/CD

#### Runner not active

**Symptome**
Les jobs dans Forgejo restent indefiniment en etat `Pending` (file d'attente).
Aucun log n'est genere pour le job.

**Diagnostic**
1. Verifier le statut du runner systemd sur le PC hote :
   ```bash
   systemctl --user status forgejo-runner.service
   journalctl --user -u forgejo-runner.service -n 50 --no-pager
   ```
2. Verifier si le runner est enregistre aupres de Forgejo :
   ```bash
   curl -sf http://localhost:3000/api/v1/runners
   ```
3. Verifier les labels du runner :
   ```bash
   cat /opt/asip/.runner-home/config.yaml | grep labels
   ```

**Cause**
- Le service systemd user `forgejo-runner.service` est arrete ou a crash.
- Le runner n'est pas enregistre (token invalide, URL Forgejo incorrecte).
- Le label du workflow (`ubuntu-latest` ou `ansible`) ne correspond pas aux labels du runner.
- Docker n'est pas accessible par l'utilisateur qui fait tourner le runner.

**Solution**
- Redemarrer le runner :
  ```bash
  systemctl --user restart forgejo-runner.service
  systemctl --user status forgejo-runner.service
  ```
- Verifier la connectivite Docker :
  ```bash
  docker ps
  ```
- Verifier l'enregistrement du runner :
  ```bash
  forgejo-runner register --instance http://localhost:3000 --token <TOKEN>
  ```

**Prevention**
- Configurer le service systemd avec `Restart=always`.
- S'assurer que Docker est demarre avant le runner (`After=docker.service`).
- Documenter l'architecture runner : le runner tourne sur le PC hote en mode systemd user, pas en LXC.

---

#### Missing tools in container

**Symptome**
```
/bin/sh: 1: aws: not found
/bin/sh: 1: jq: not found
pip3: command not found
```
Le job CI echoue sur une commande de base alors que le workflow specifie `runs-on: ubuntu-latest`.

**Diagnostic**
1. Connecter au container du job (si possible) ou ajouter des etapes de debug :
   ```yaml
   - name: Debug environment
     run: |
       cat /etc/os-release
       which aws || true
       which jq || true
       which pip3 || true
   ```
2. Verifier le label utilise :
   ```yaml
   runs-on: ubuntu-latest
   ```

**Cause**
Le label `ubuntu-latest` dans le runner Forgejo est mappe sur l'image Docker `node:22-bookworm`, qui est basee sur **Debian Bookworm**, pas Ubuntu. Cette image ne contient pas les outils systeme usuels (`jq`, `awscli`, `ansible`, `terraform`) qui sont presents sur une image Ubuntu classique.

**Solution**
Installer explicitement les outils necessaires dans chaque job :
```yaml
- name: Install tools
  run: |
    apt-get update && apt-get install -y jq curl unzip python3-pip
    pip install awscli --break-system-packages || pip install awscli
```
Ou mieux, creer une image Docker personnalisee incluant tous les outils (Trivy, Terraform, Ansible, AWS CLI, jq) et definir un label custom :
```yaml
runner:
  labels:
    - "asip-ci:docker://myregistry/asip-ci-runner:latest"
```

**Prevention**
- Documenter clairement dans CI-CD.md que `ubuntu-latest` signifie `node:22-bookworm`.
- Ne jamais supposer la presence d'un binaire systeme sans etape d'installation explicite dans le workflow.
- Considerer la creation d'une image CI interne pre-bakee.

---

### Sécurité

#### Trivy CRITICAL

**Symptome**
Le pipeline `security-scan.yml` echoue avec :
```
BLOCKING: Critical vulnerabilities found!
```
Le merge est bloque par la protection de branche.

**Diagnostic**
1. Telecharger et consulter le rapport JSON :
   ```bash
   cat trivy-fs-results.json | python3 -m json.tool | grep -A 10 '"Severity": "CRITICAL"'
   ```
2. Identifier le package ou l'image impacte :
   ```bash
   cat trivy-image-vaultwarden-server-latest.json | jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL") | {PkgName, VulnerabilityID, Title}'
   ```
3. Verifier si une mise a jour existe :
   ```bash
   docker pull vaultwarden/server:latest
   trivy image vaultwarden/server:latest --severity CRITICAL --format json --output /tmp/recheck.json
   ```

**Cause**
Trivy a detecte au moins une vulnerabilite de severite CRITICAL dans le filesystem du repo ou dans une image container analysee. La pipeline implemente un `pipeline gate` : si `critical > 0`, le job retourne `exit 1`.

**Solution**
- Patcher la vulnerabilite :
  - **Image container** : mettre a jour l'image vers une version corrigee (modifier le tag dans le docker-compose ou le manifest).
  - **Package systeme** : mettre a jour via le gestionnaire de paquets (`apt update && apt upgrade`).
  - **Dependance code** : mettre a jour la dependance (`pip install --upgrade`, `npm audit fix`).
- Si la vulnerabilite est un faux positif ou non applicable a l'usage reel, documenter un `trivyignore` (mais eviter de masquer systematiquement les CRITICAL) :
  ```bash
  echo "CVE-XXXX-YYYY" > .trivyignore
  ```
- Relancer le pipeline pour valider :
  ```bash
  forgejo-cli run workflow --name security-scan.yml
  ```

**Prevention**
- Maintenir les images et les packages a jour.
- Utiliser des tags fixes plutot que `latest` pour les images de production, avec un processus de revue des CVE avant upgrade.
- Activer le schedule quotidien (`cron: '0 3 * * *'`) pour detecter les nouvelles vulnerabilites rapidement.

---

#### Goss validation failed

**Symptome**
```bash
goss -g /etc/goss/goss.yaml validate --format json
```
Retourne `failed-count > 0`. `verify.sh` affiche `Goss compliance check failed`. La pipeline `drift-check.yml` echoue.

**Diagnostic**
1. Executer la validation avec le detail des erreurs :
   ```bash
   goss -g /etc/goss/goss.yaml validate --format documentation
   ```
2. Verifier les resultats JSON pour voir les tests specifiques en echec :
   ```bash
   goss -g /etc/goss/goss.yaml validate --format json | python3 -m json.tool | grep -A 5 '"successful": false'
   ```
3. Verifier si l'echec est temporel (service pas encore demarre) :
   ```bash
   systemctl status <service_en_erreur>
   ```

**Cause**
- **Timing** : Le service teste (ex: sshd, nginx) n'est pas encore actif au moment du test Goss. `verify.sh` et `demo-autonomous.sh` lancent Goss immediatement apres le provisionnement.
- **Drift reel** : Un fichier de configuration ou une permission a ete modifiee manuellement ou par un autre processus (ex: `PermitRootLogin yes` au lieu de `no`).
- **Package manquant** : Un package attendu n'est pas installe (`fail2ban`, `aide`, etc.).

**Solution**
- **Timing** : Attendre 30 secondes et relancer :
  ```bash
  sleep 30
  goss -g /etc/goss/goss.yaml validate
  ```
- **Drift reel** : Laisser le watchdog declencher la remediation Ansible automatique, ou lancer manuellement :
  ```bash
  ansible-playbook ansible/site.yml -i ansible/inventory/prod.yml \
    --private-key ~/.ssh/id_ed25519 -u ansible -b --tags hardening --limit <host>
  ```
- **Package manquant** : Installer le package manquant et relancer le playbook complet.

**Prevention**
- Utiliser un delai raisonnable apres le boot ou redemarrage de service avant de lancer Goss.
- S'assurer que les regles Goss sont alignees avec le role Ansible (pas de tests sur des elements volatiles comme la date de derniere connexion ou des PID).
- Activer le polling regulier du watchdog pour detecter la derive avant que la CI ne la remarque.

---

## Fichiers de log a consulter

| Composant | Fichier / Commande | Usage |
|-----------|-------------------|-------|
| Terraform | `TF_LOG=DEBUG terraform apply` | Traces detaillees des appels API Proxmox |
| Ansible | `ansible-playbook ... -vvvv` | Traces SSH et module execution |
| Ansible Vault | Aucun (erreur a l'init) | `ANSIBLE_VERBOSITY=3` pour le debug |
| Proxmox | `/var/log/syslog` sur `pve` | Logs des taches (vzdump, qm clone) |
| Proxmox | `pvesh get /cluster/tasks` | Liste des taches en cours |
| LocalStack | `docker logs localstack-main` | Logs de demarrage des services S3/IAM/STS |
| LocalStack | `docker inspect localstack-main --format='{{.State.Health}}'` | Etat du healthcheck Docker |
| MCP Watchdog | `journalctl -u mcp-watchdog` | Logs du service Python |
| MCP Watchdog | `/var/log/watchdog/audit.json` | Historique des remediations |
| MCP Watchdog | `/var/log/watchdog/poller.log` | Logs du poller Goss |
| Forgejo Runner | `journalctl --user -u forgejo-runner.service` | Logs de registration et execution des jobs |
| Forgejo | `/var/lib/forgejo/log/` | Logs applicatifs Forgejo |
| Goss | `/var/log/goss/goss-results.json` | Resultats JSON de la derniere validation |
| Trivy | `trivy-*.json` (artifacts CI) | Rapports de vulnerabilites detailles |
| rclone | `rclone ls --verbose ...` | Debug des appels S3 |

---

## Repertoires de configuration utiles

- `terraform/main.tf` : Configuration VM Proxmox + backend HTTP
- `ansible/inventory/prod.yml` : Inventaire des hotes
- `ansible/roles/mcp-watchdog/` : Role de deploiement du watchdog
- `mcp-agent/config.yaml` : Configuration du polling et des seuils de remediation
- `.forgejo/workflows/` : Pipelines CI/CD
- `localstack/docker-compose.yml` : Stack LocalStack S3 + IAM
- `scripts/deploy.sh` : Script d'orchestration complet
- `scripts/verify.sh` : Script de verification post-deploiement
