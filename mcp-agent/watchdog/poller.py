import subprocess
import json
import logging
import yaml
from typing import Optional
from watchdog.state import StateEngine

logger = logging.getLogger("asip.watchdog.poller")


class Poller:
    def __init__(self, config: dict, state: StateEngine, inventory: dict):
        self.config = config
        self.state = state
        self.inventory = inventory
        self.ssh_user = config.get("ssh_user", "ansible")
        self.ssh_key = config.get("ssh_key", "~/.ssh/id_ed25519")
        self.goss_results_path = config.get("goss_results_path", "/var/log/goss/goss-results.json")
        self.timeout = config.get("timeout_seconds", 10)

    def poll_all_hosts(self) -> list[dict]:
        results = []
        for host, host_data in self.inventory.items():
            ip = host_data.get("ansible_host", host_data.get("ip", ""))
            if not ip or "router" in host:
                continue
            result = self.poll_host(host, ip)
            results.append(result)
        return results

    def poll_host(self, host: str, ip: str) -> dict:
        logger.info(f"Polling {host} ({ip})...")
        try:
            cmd = [
                "ssh",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", f"ConnectTimeout={self.timeout}",
                "-o", "BatchMode=yes",
                "-i", os.path.expanduser(self.ssh_key),
                f"{self.ssh_user}@{ip}",
                f"cat {self.goss_results_path}",
            ]
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=self.timeout + 5
            )
            if result.returncode != 0:
                logger.warning(f"Failed to poll {host}: {result.stderr.strip()}")
                return {"host": host, "ip": ip, "status": "unreachable", "failed": 0}
            goss_data = json.loads(result.stdout)
            summary = goss_data.get("summary", {})
            failed_count = summary.get("failed-count", summary.get("failed", 0))
            if failed_count > 0:
                logger.warning(f"Drift detected on {host}: {failed_count} checks failed")
                self.state.record_drift(host, ip, failed_count, goss_data)
            else:
                logger.info(f"{host}: all checks passed")
                self.state.record_ok(host, ip)
            return {"host": host, "ip": ip, "status": "drift" if failed_count > 0 else "ok", "failed": failed_count}
        except Exception as e:
            logger.error(f"Error polling {host}: {e}")
            return {"host": host, "ip": ip, "status": "error", "failed": 0}


import os