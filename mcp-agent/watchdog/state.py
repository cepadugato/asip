from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional
import json
import os


@dataclass
class HostState:
    host: str
    ip: str
    last_ok: Optional[datetime] = None
    last_drift: Optional[datetime] = None
    last_remediation: Optional[datetime] = None
    drift_count_24h: int = 0
    remediation_count_24h: int = 0
    consecutive_failures: int = 0
    current_checks: dict = field(default_factory=dict)


class StateEngine:
    def __init__(self, state_dir: str = "/var/lib/asip/watchdog"):
        self.state_dir = state_dir
        self.hosts: dict[str, HostState] = {}
        os.makedirs(state_dir, exist_ok=True)
        self._load_state()

    def _state_file(self) -> str:
        return os.path.join(self.state_dir, "state.json")

    def _load_state(self):
        path = self._state_file()
        if os.path.exists(path):
            with open(path) as f:
                data = json.load(f)
            for host_data in data.get("hosts", []):
                hs = HostState(
                    host=host_data["host"],
                    ip=host_data["ip"],
                    last_ok=self._parse_dt(host_data.get("last_ok")),
                    last_drift=self._parse_dt(host_data.get("last_drift")),
                    last_remediation=self._parse_dt(host_data.get("last_remediation")),
                    drift_count_24h=host_data.get("drift_count_24h", 0),
                    remediation_count_24h=host_data.get("remediation_count_24h", 0),
                    consecutive_failures=host_data.get("consecutive_failures", 0),
                    current_checks=host_data.get("current_checks", {}),
                )
                self.hosts[hs.host] = hs

    def save_state(self):
        data = {"hosts": []}
        for hs in self.hosts.values():
            data["hosts"].append({
                "host": hs.host,
                "ip": hs.ip,
                "last_ok": hs.last_ok.isoformat() if hs.last_ok else None,
                "last_drift": hs.last_drift.isoformat() if hs.last_drift else None,
                "last_remediation": hs.last_remediation.isoformat() if hs.last_remediation else None,
                "drift_count_24h": hs.drift_count_24h,
                "remediation_count_24h": hs.remediation_count_24h,
                "consecutive_failures": hs.consecutive_failures,
                "current_checks": hs.current_checks,
            })
        with open(self._state_file(), "w") as f:
            json.dump(data, f, indent=2)

    @staticmethod
    def _parse_dt(val: Optional[str]) -> Optional[datetime]:
        if val is None:
            return None
        return datetime.fromisoformat(val)

    def get_or_create(self, host: str, ip: str) -> HostState:
        if host not in self.hosts:
            self.hosts[host] = HostState(host=host, ip=ip)
        return self.hosts[host]

    def record_ok(self, host: str, ip: str):
        hs = self.get_or_create(host, ip)
        hs.last_ok = datetime.now()
        hs.consecutive_failures = 0
        self.save_state()

    def record_drift(self, host: str, ip: str, failed_count: int, checks: dict):
        hs = self.get_or_create(host, ip)
        hs.last_drift = datetime.now()
        hs.drift_count_24h += 1
        hs.consecutive_failures += 1
        hs.current_checks = checks
        self.save_state()

    def record_remediation(self, host: str, ip: str):
        hs = self.get_or_create(host, ip)
        hs.last_remediation = datetime.now()
        hs.remediation_count_24h += 1
        self.save_state()

    def can_remediate(self, host: str, cooldown_seconds: int, max_24h: int) -> bool:
        hs = self.hosts.get(host)
        if hs is None:
            return True
        if hs.last_remediation:
            elapsed = (datetime.now() - hs.last_remediation).total_seconds()
            if elapsed < cooldown_seconds:
                return False
        if hs.remediation_count_24h >= max_24h:
            return False
        return True

    def get_status(self) -> dict:
        result = {}
        for host, hs in self.hosts.items():
            result[host] = {
                "ip": hs.ip,
                "status": "OK" if hs.consecutive_failures == 0 else "DRIFT",
                "last_ok": hs.last_ok.isoformat() if hs.last_ok else None,
                "last_drift": hs.last_drift.isoformat() if hs.last_drift else None,
                "last_remediation": hs.last_remediation.isoformat() if hs.last_remediation else None,
                "drift_count_24h": hs.drift_count_24h,
                "remediation_count_24h": hs.remediation_count_24h,
                "consecutive_failures": hs.consecutive_failures,
                "checks": hs.current_checks,
            }
        return result