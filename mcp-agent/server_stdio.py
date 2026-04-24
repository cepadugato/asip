#!/usr/bin/env python3
"""ASIP Watchdog MCP stdio server.

Exposes the same toolset as the HTTP server via the official MCP SDK
(FastMCP) over stdio transport.  All logs go to stderr so stdout stays
pure JSON-RPC.
"""

import json
import logging
import os
import sys

import yaml
from mcp.server.fastmcp import FastMCP

from watchdog.state import StateEngine
from watchdog.remediation import RemediationEngine
from watchdog.poller import Poller

# ---------------------------------------------------------------------------
# Config / inventory helpers (same logic as server.py)
# ---------------------------------------------------------------------------


def _load_config(config_path: str) -> dict:
    with open(config_path) as f:
        return yaml.safe_load(f)


def _load_inventory(inventory_path: str) -> dict:
    result = {}
    if not os.path.exists(inventory_path):
        return result
    with open(inventory_path) as f:
        inv = yaml.safe_load(f)
    hosts = inv.get("all", {}).get("hosts", {})
    for host_name, host_data in hosts.items():
        ip = host_data.get("ansible_host", "") if isinstance(host_data, dict) else ""
        result[host_name] = {
            "ip": ip,
            "data": host_data if isinstance(host_data, dict) else {},
        }
    return result


def _resolve_config_path() -> str:
    env_path = os.environ.get("WATCHDOG_CONFIG")
    if env_path and os.path.exists(env_path):
        return env_path

    candidates = [
        os.path.join(os.path.dirname(__file__), "config.yaml"),
        "/etc/asip/watchdog/config.yaml",
        "config.yaml",
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    raise FileNotFoundError("config.yaml not found")


# ---------------------------------------------------------------------------
# Logging MUST target stderr exclusively -- stdout is reserved for JSON-RPC.
# ---------------------------------------------------------------------------

config = _load_config(_resolve_config_path())

log_cfg = config.get("logging", {})
log_level = getattr(logging, log_cfg.get("level", "INFO"), logging.INFO)

logging.basicConfig(
    level=log_level,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stderr)],
    force=True,
)

logger = logging.getLogger("asip.watchdog.mcp")

# ---------------------------------------------------------------------------
# Initialise engines once at import time (lightweight).
# ---------------------------------------------------------------------------

state_dir = os.environ.get("WATCHDOG_STATE_DIR", "/var/lib/asip/watchdog")
# Fallback to a local directory if the system path is not writable
if not os.access(os.path.dirname(state_dir) or state_dir, os.W_OK):
    state_dir = os.path.join(os.path.dirname(__file__), ".watchdog_state")
    os.makedirs(state_dir, exist_ok=True)

state = StateEngine(state_dir=state_dir)

remediation_cfg = config.get("remediation", {}).copy()
remediation_cfg["log_dir"] = log_cfg.get("dir", "/var/log/watchdog")
remediation = RemediationEngine(remediation_cfg, state)

inv_path = remediation_cfg.get("ansible_inventory", "/opt/asip/ansible/inventory/prod.yml")
inventory = _load_inventory(inv_path)

poller = Poller(config.get("poller", {}), state, inventory)

logger.info("ASIP Watchdog MCP stdio server initialised")

# ---------------------------------------------------------------------------
# FastMCP application
# ---------------------------------------------------------------------------

mcp = FastMCP("asip-watchdog")


@mcp.tool()
def watchdog_status() -> dict:
    """Get the status of all monitored hosts (last OK, drift count, remediation count)."""
    return state.get_status()


@mcp.tool()
def watchdog_host_status(host: str) -> dict:
    """Get detailed status of a specific host."""
    status = state.get_status()
    return status.get(host, {"error": f"Host {host} not found"})


@mcp.tool()
def watchdog_drift_history(host: str, hours: int = 24) -> dict:
    """Get drift history for a host over the last N hours."""
    log_dir = remediation_cfg.get("log_dir", "/var/log/watchdog")
    audit_file = os.path.join(log_dir, "audit.json")
    if not os.path.exists(audit_file):
        return {"entries": []}

    with open(audit_file) as f:
        try:
            entries = json.load(f)
        except json.JSONDecodeError:
            return {"entries": []}

    # Rough filter: assume ~12 entries per hour (5-min polling).
    # If host is specified we also filter by host.
    limit = max(hours * 12, 1)
    recent = entries[-limit:]
    if host:
        recent = [e for e in recent if e.get("host") == host]
    return {"entries": recent}


@mcp.tool()
def watchdog_remediate(host: str, tags: str = "") -> dict:
    """Trigger manual remediation for a host."""
    if not remediation.can_remediate(host):
        return {"error": "Cannot remediate: cooldown or max retries reached"}
    return remediation.remediate(host, tags=tags)


@mcp.tool()
def watchdog_force_ansible(tags: str = "", limit: str = "") -> dict:
    """Force run an Ansible playbook with specific tags and limit."""
    host = limit
    if not host:
        return {"error": "Missing 'limit' parameter (host to target)"}
    return remediation.remediate(host, tags=tags)


@mcp.tool()
def watchdog_run_goss(host: str) -> dict:
    """Run a remote goss check on a host and return the result."""
    host_data = inventory.get(host, {})
    ip = host_data.get("ip", "")
    if not ip:
        # Fallback: try to treat host as an IP
        ip = host
    return poller.poll_host(host, ip)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run(transport="stdio")
