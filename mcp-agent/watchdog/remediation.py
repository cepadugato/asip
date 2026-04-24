import subprocess
import json
import logging
import os
from datetime import datetime
from typing import Optional

from watchdog.state import HostState

logger = logging.getLogger("asip.watchdog.remediation")


class RemediationEngine:
    def __init__(self, config: dict, state):
        self.config = config
        self.state = state
        self.playbook = config.get("ansible_playbook", "/opt/asip/ansible/site.yml")
        self.inventory = config.get("ansible_inventory", "/opt/asip/ansible/inventory/prod.yml")
        self.private_key = os.path.expanduser(config.get("ansible_private_key", "~/.ssh/id_ed25519"))
        self.vault_password_file = os.path.expanduser(
            config.get("ansible_vault_password_file", "~/.vault_pass")
        )
        self.ansible_user = config.get("ansible_user", "ansible")
        self.log_dir = config.get("log_dir", "/var/log/watchdog")

    def can_remediate(self, host: str) -> bool:
        cooldown = self.config.get("cooldown_seconds", 600)
        max_24h = self.config.get("max_remediations_24h", 3)
        return self.state.can_remediate(host, cooldown, max_24h)

    def remediate(self, host: str, tags: str = "") -> dict:
        logger.info(f"Starting remediation for {host} with tags='{tags}'")

        hs = self.state.hosts.get(host)
        ip = hs.ip if hs else ""
        self.state.record_remediation(host, ip)

        cmd = self._build_ansible_command(host, tags)
        log_file = os.path.join(
            self.log_dir,
            f"remediation_{host}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        )

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=600
            )
            success = result.returncode == 0

            with open(log_file, "w") as f:
                f.write(f"Command: {' '.join(cmd)}\n")
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")

            audit_entry = {
                "timestamp": datetime.now().isoformat(),
                "event": "remediation_completed" if success else "remediation_failed",
                "host": host,
                "tags": tags,
                "action": " ".join(cmd),
                "exit_code": result.returncode,
                "log_file": log_file,
            }
            self._write_audit(audit_entry)

            logger.info(f"Remediation {'succeeded' if success else 'failed'} for {host}")
            return {
                "success": success,
                "exit_code": result.returncode,
                "log_file": log_file,
            }
        except subprocess.TimeoutExpired:
            logger.error(f"Remediation timeout for {host}")
            return {"success": False, "error": "timeout", "log_file": log_file}
        except Exception as e:
            logger.error(f"Remediation error for {host}: {e}")
            return {"success": False, "error": str(e)}

    def _build_ansible_command(self, host: str, tags: str = "") -> list:
        cmd = [
            "ansible-playbook",
            self.playbook,
            "-i", self.inventory,
            "--private-key", self.private_key,
            "-u", self.ansible_user,
            "-b",
            "--limit", host,
        ]

        if os.path.exists(self.vault_password_file):
            cmd.extend(["--vault-password-file", self.vault_password_file])

        if tags:
            cmd.extend(["--tags", tags])

        return cmd

    def _write_audit(self, entry: dict):
        audit_file = os.path.join(self.log_dir, "audit.json")
        entries = []
        if os.path.exists(audit_file):
            with open(audit_file) as f:
                try:
                    entries = json.load(f)
                except json.JSONDecodeError:
                    entries = []
        entries.append(entry)
        with open(audit_file, "w") as f:
            json.dump(entries, f, indent=2)
