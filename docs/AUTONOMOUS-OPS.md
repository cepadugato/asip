# Opérations Autonomes A.S.I.P.

## Principe

Le pilier **AUTONOMOUS OPS** d'A.S.I.P. met en œuvre un agent IA (GLM 5.1 via MCP) capable de **surveiller** l'infrastructure, **détecter** les dérives de configuration, et **auto-remédier** en relançant les playbooks Ansible appropriés — sans intervention humaine pour les incidents de basse et moyenne sévérité.

Ce n'est pas une automatisation aveugle : l'agent évalue la sévérité, choisit l'action proportionnée, et documente chaque intervention.

---

## Architecture du MCP Watchdog

```
┌────────────────────────────────────────────────────────────────┐
│                    MCP WATCHDOG ARCHITECTURE                   │
│                                                                │
│  ┌───────────────┐                    ┌──────────────────┐    │
│  │  OpenCode     │  MCP Protocol      │  mcp-watchdog    │    │
│  │  (Agent IA)   │ ◄────────────────► │  (LXC 119)       │    │
│  │  GLM 5.1      │  (stdio JSON-RPC)  │  203.0.113.50 │    │
│  │               │                    │  server.py :8080 │    │
│  └───────────────┘                    └────────┬─────────┘    │
│                                                 │              │
│  ┌──────────────────────────────────────────────┼──────────┐  │
│  │              REMEDIATION ENGINE               │          │  │
│  │                                              │          │  │
│  │  ┌─────────────┐    ┌──────────────────┐     │          │  │
│  │  │   POLLER    │    │  WEBHOOK LISTENER │     │          │  │
│  │  │  (goss-poll │    │  (POST /webhook)  │     │          │  │
│  │  │   .sh/timer)│    │  Real-time       │     │          │  │
│  │  └──────┬──────┘    └────────┬──────────┘     │          │  │
│  │         │                    │                │          │  │
│  │  ┌──────▼────────────────────▼──────────┐    │          │  │
│  │  │         STATE ENGINE                   │    │          │  │
│  │  │  • Dernière validation par VM        │    │          │  │
│  │  │  • Historique des drifts (JSON)       │    │          │  │
│  │  │  • Nombre de remédiations            │    │          │  │
│  │  │  • Cooldown (pas de re-run < 10 min) │    │          │  │
│  │  └──────────────┬───────────────────────┘    │          │  │
│  │                  │                            │          │  │
│  │  ┌──────────────▼───────────────────────┐    │          │  │
│  │  │         REMEDIATION POLICY            │    │          │  │
│  │  │                                      │    │          │  │
│  │  │  0 failed  → Log OK                  │    │          │  │
│  │  │  1-3 failed → --tags <role>          │    │          │  │
│  │  │  4+ failed → site.yml complet        │    │          │  │
│  │  │  Recidive  → Alerte P2 + log         │    │          │  │
│  │  └──────────────────────────────────────┘    │          │  │
│  └──────────────────────────────────────────────┘    │          │
│                                                      │          │
│  ┌───────────────────────────────────────────────────┘          │
│  │  ANSIBLE EXECUTOR                                             │
│  │  ansible-playbook -i inventory/prod.yml site.yml             │
│  │    --tags <role> --limit <host>                              │
│  │    --private-key ~/.ssh/id_ed25519                           │
│  │    --vault-password-file ~/.vault_pass                       │
│  └──────────────────────────────────────────────────────────────┘
└────────────────────────────────────────────────────────────────┘
```

---

## Composants détaillés

### 1. Poller (polling cyclique)

Le poller s'exécute toutes les 5 minutes via un timer systemd. Il tourne localement sur LXC 119 (mcp-watchdog) et exécute Goss directement pour chaque hôte de l'inventaire :

1. Exécute `goss validate` localement via `goss-poll.sh` qui enrichit les résultats (ajoute horodatage, hostname, IP)
2. Analyse `/var/log/goss/goss-results.json` (dernier résultat Goss)
3. Évalue le `failed-count`
4. Si drift détecté, transmet au State Engine

```python
# Extrait du poller
def poll_host(host_ip: str) -> DriftResult:
    """Exécute Goss localement et analyse les résultats enrichis."""
    result = subprocess.run(
        ["goss", "-g", f"/etc/goss/{host_ip}.yaml", "validate", "--format", "json"],
        capture_output=True, text=True
    )
    goss_data = json.loads(result.stdout)
    failed = goss_data.get("summary", {}).get("failed-count", 0)
    return DriftResult(host=host_ip, failed_count=failed, checks=goss_data)
```

### 2. Webhook Listener (push temps réel)

Le webhook listener est un endpoint FastAPI qui reçoit les alertes push des VMs. Chaque VM configure son timer Goss pour POSTer vers le watchdog après chaque validation :

```
POST http://203.0.113.50:8080/webhook/goss
Content-Type: application/json

{
  "host": "bastion",
  "ip": "192.0.2.5",
  "timestamp": "2026-04-21T14:30:00Z",
  "summary": {
    "total-count": 15,
    "failed-count": 2,
    "passed-count": 13
  },
  "failed_checks": [
    {"type": "file", "resource": "/etc/ssh/sshd_config", "property": "contains", "expected": "!/PermitRootLogin yes/"},
    {"type": "service", "resource": "crowdsec", "property": "running", "expected": "true"}
  ]
}
```

Avantage : le webhook est **immédiat** (< 30s) vs le poller qui a un délai max de 5 minutes. Le poller sert de filet de sécurité (catch-all).

### 3. State Engine

Le State Engine maintient en mémoire l'état de surveillance de chaque VM :

```python
@dataclass
class HostState:
    host: str
    ip: str
    last_ok: datetime | None          # Dernière validation OK
    last_drift: datetime | None       # Dernier drift détecté
    last_remediation: datetime | None  # Dernière remédiation exécutée
    drift_count_24h: int              # Nombre de drifts sur 24h
    remediation_count_24h: int        # Nombre de remédiations sur 24h
    consecutive_failures: int          # Échecs consécutifs
```

Règles de gestion :
- **Cooldown** : Pas de remédiation si la dernière date de moins de 10 minutes (évite les boucles)
- **Récidive** : Si 3+ remédiations sur 24h pour le même host → Alerte P2, arrêt auto-remédiation
- **Escalade** : Si 5+ échecs consécutifs → Alerte P1, arrêt auto-remédiation, notification ingénieur

### 4. Remediation Policy

| Condition | Action | Tags Ansible |
|-----------|--------|-------------|
| 0 check échoué | Rien (log OK) | — |
| 1-3 checks SSH/config | Remédiation ciblée | `hardening` |
| 1-3 checks service | Restart via Ansible | Rôle du service |
| 4+ checks | Playbook complet | `site.yml` (tous) |
| Récidive (3x/24h) | Alerte P2, pas d'auto-fix | — |
| 5+ échecs consécutifs | Alerte P1, arrêt auto | — |

### 5. Ansible Executor

L'exécuteur Ansible lance les playbooks avec les paramètres appropriés :

```bash
# Remédiation ciblée (1-3 checks)
ansible-playbook -i inventory/prod.yml site.yml \
  --tags hardening \
  --limit bastion \
  --private-key ~/.ssh/id_ed25519 \
  --vault-password-file ~/.vault_pass

# Remédiation complète (4+ checks)
ansible-playbook -i inventory/prod.yml site.yml \
  --private-key ~/.ssh/id_ed25519 \
  --vault-password-file ~/.vault_pass
```

Après remédiation, le poller vérifie au prochain cycle (5 min) que le drift est corrigé.

---

## MCP Tools exposés

Le serveur MCP watchdog expose les outils suivants au LLM (GLM 5.1) via le protocole MCP :

| Tool | Paramètres | Description |
|------|-----------|-------------|
| `watchdog_status` | — | État de surveillance de toutes les VMs (last OK, drift count, en cours) |
| `watchdog_host_status` | `host: str` | État détaillé d'une VM spécifique |
| `watchdog_drift_history` | `host: str, hours: int = 24` | Historique des drifts détectés sur une VM |
| `watchdog_remediate` | `host: str, tags: str = ""` | Déclencher manuellement une remédiation |
| `watchdog_force_ansible` | `playbook: str, tags: str, limit: str` | Forcer un playbook Ansible spécifique |
| `watchdog_run_goss` | `host: str` | Exécuter une validation Goss immédiate sur une VM |
| `watchdog_acknowledge` | `host: str, incident_id: str` | Acquitter un incident (reset compteur récidive) |

### Exemple d'interaction LLM

```
Utilisateur: "Est-ce que l'infra est OK ?"

LLM → appelle watchdog_status():
  Résultat: {
    "hosts": {
      "bastion": {"status": "OK", "last_check": "2026-04-21T14:30:00Z"},
      "ad-server": {"status": "DRIFT", "failed": 2, "last_remediation": "2026-04-21T14:25:00Z"},
      ...
    },
    "summary": {"ok": 17, "drift": 1, "unknown": 2}
  }

LLM: "L'infrastructure est globalement saine. 17 VMs sur 20 sont conformes.
      Le serveur AD (ad-server) présente un drift avec 2 checks échoués.
      Une remédiation a déjà été exécutée à 14:25. Je vérifie si elle a corrigé le problème."

LLM → appelle watchdog_host_status(host="ad-server"):
  Résultat: {"status": "REMEDIATING", "last_remediation": "5 min ago", "checks_failed": ["service.smbd.running", "file./etc/samba/smb.conf.contains"]}

LLM: "Le serveur AD est en cours de remédiation automatique. Les checks échoués portent
      sur le service Samba et sa configuration. La correction a été lancée il y a 5 minutes.
      Le prochain cycle de vérification dans 2 minutes confirmera la résolution."
```

---

## Configuration

### config.yaml (mcp-agent)

```yaml
# MCP Watchdog Configuration
poller:
  interval_seconds: 300      # 5 minutes
  ssh_user: ansible
  ssh_key: ~/.ssh/id_ed25519
  goss_results_path: /var/log/goss/goss-results.json

webhook:
  host: 0.0.0.0
  port: 8080
  endpoint: /webhook/goss

remediation:
  cooldown_seconds: 600      # 10 minutes entre 2 remédiations
  max_remediations_24h: 3    # Seuil de récidive
  max_consecutive_failures: 5 # Seuil d'escalade P1

ansible:
  playbook: /opt/asip/ansible/site.yml
  inventory: /opt/asip/ansible/inventory/prod.yml
  private_key: ~/.ssh/id_ed25519
  vault_password_file: ~/.vault_pass
  
  tag_mapping:
    ssh_config: hardening
    service_failure: ""  # déterminé dynamiquement par le rôle du host
    file_integrity: hardening
    package_missing: ""  # déterminé dynamiquement

hosts:
  # Généré dynamiquement depuis l'inventaire Ansible
  # Chaque entrée contient: ip, role, expected_tags
```

### Service systemd

```ini
# /etc/systemd/system/mcp-watchdog.service
[Unit]
Description=A.S.I.P. MCP Watchdog — Autonomous Operations Agent
After=network.target

[Service]
Type=simple
User=watchdog
Group=watchdog
WorkingDirectory=/opt/asip/mcp-agent
ExecStart=/opt/asip/mcp-agent/venv/bin/python server.py --config /opt/asip/mcp-agent/config.yaml
Restart=always
RestartSec=10
Environment=WATCHDOG_CONFIG=/opt/asip/mcp-agent/config.yaml

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/mcp-watchdog-poll.timer
[Unit]
Description=A.S.I.P. Watchdog Poll Timer

[Timer]
OnBootSec=60
OnUnitActiveSec=300
AccuracySec=30

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/goss-poll.service
[Unit]
Description=A.S.I.P. Goss Poll — Local Validation
After=network.target

[Service]
Type=oneshot
User=watchdog
Group=watchdog
ExecStart=/opt/asip/scripts/goss-poll.sh --config /opt/asip/mcp-agent/config.yaml
```

---

## Journal d'audit

Chaque action du watchdog est journalisée dans `/var/log/watchdog/` :

```json
{
  "timestamp": "2026-04-21T14:30:15Z",
  "event": "drift_detected",
  "host": "bastion",
  "ip": "192.0.2.5",
  "source": "webhook",
  "failed_checks": 2,
  "checks": ["file./etc/ssh/sshd_config", "service.crowdsec.running"]
}
{
  "timestamp": "2026-04-21T14:30:20Z",
  "event": "remediation_started",
  "host": "bastion",
  "action": "ansible-playbook --tags hardening --limit bastion"
}
{
  "timestamp": "2026-04-21T14:32:45Z",
  "event": "remediation_completed",
  "host": "bastion",
  "exit_code": 0,
  "duration_seconds": 145
}
{
  "timestamp": "2026-04-21T14:35:00Z",
  "event": "drift_resolved",
  "host": "bastion",
  "source": "poller",
  "failed_checks": 0
}
```

---

## Limites et garde-fous

| Limite | Valeur | Raison |
|--------|--------|--------|
| Cooldown entre remédiations | 10 min | Prévient les boucles de remédiation |
| Max remédiations/24h par host | 3 | Prévient la fuite de réparations |
| Max échecs consécutifs avant escalade | 5 | Un problème persistant nécessite un humain |
| Pas d'auto-fix sur les failles CRITICAL containers | — | Risque de casser le service |
| Pas d'auto-fix sur AIDE violations | — | Nécessite investigation manuelle |
| Pas de redémarrage de l'OPNsense router | — | Risque de coupure réseau |
| Pas de modification Proxmox (create/delete VM) | — | Action irréversible |

Ces limites garantissent que l'agent IA reste dans un périmètre maîtrisé et qu'un ingénieur est toujours alerté pour les situations qui dépassent la capacité d'auto-remédiation.