#!/usr/bin/env python3
import argparse
import json
import logging
import os
import sys
import yaml

import uvicorn
from fastapi import FastAPI

from watchdog.state import StateEngine
from watchdog.poller import Poller
from watchdog.webhook_listener import app as webhook_app, init_engines
from watchdog.remediation import RemediationEngine


def load_config(config_path: str) -> dict:
    with open(config_path) as f:
        return yaml.safe_load(f)


def load_inventory(inventory_path: str) -> dict:
    result = {}
    with open(inventory_path) as f:
        inv = yaml.safe_load(f)
    hosts = inv.get("all", {}).get("hosts", {})
    for host_name, host_data in hosts.items():
        ip = host_data.get("ansible_host", "") if isinstance(host_data, dict) else ""
        result[host_name] = {"ip": ip, "data": host_data if isinstance(host_data, dict) else {}}
    return result


def create_mcp_app(config_path: str):
    config = load_config(config_path)
    state = StateEngine()
    remediation = RemediationEngine(config.get("remediation", {}), state)
    return state, remediation, config


def run_server(config_path: str):
    config = load_config(config_path)
    log_config = config.get("logging", {})
    log_dir = log_config.get("dir", "/var/log/watchdog")
    os.makedirs(log_dir, exist_ok=True)

    logging.basicConfig(
        level=getattr(logging, log_config.get("level", "INFO")),
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(os.path.join(log_dir, "watchdog.log")),
        ],
    )

    logger = logging.getLogger("asip.watchdog")
    logger.info("Starting ASIP MCP Watchdog server")

    state, remediation, app_config = create_mcp_app(config_path)
    inv_path = config.get("remediation", {}).get("ansible_inventory", "/opt/asip/ansible/inventory/prod.yml")
    inventory = load_inventory(inv_path)
    poller = Poller(config.get("poller", {}), state, inventory)

    init_engines(state, remediation)

    webhook_config = config.get("webhook", {})
    host = webhook_config.get("host", "0.0.0.0")
    port = webhook_config.get("port", 8080)

    logger.info(f"Webhook listener starting on {host}:{port}")
    uvicorn.run(webhook_app, host=host, port=port)


def run_poller(config_path: str):
    config = load_config(config_path)
    log_config = config.get("logging", {})
    log_dir = log_config.get("dir", "/var/log/watchdog")
    os.makedirs(log_dir, exist_ok=True)

    logging.basicConfig(
        level=getattr(logging, log_config.get("level", "INFO")),
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(os.path.join(log_dir, "poller.log")),
        ],
    )

    logger = logging.getLogger("asip.watchdog.poller")
    logger.info("Starting ASIP Watchdog poller")

    state, remediation, _ = create_mcp_app(config_path)
    inv_path = config.get("remediation", {}).get("ansible_inventory", "/opt/asip/ansible/inventory/prod.yml")
    inventory = load_inventory(inv_path)
    poller = Poller(config.get("poller", {}), state, inventory)

    results = poller.poll_all_hosts()
    for r in results:
        logger.info(f"  {r['host']}: {r['status']} (failed={r['failed']})")

    state.save_state()
    logger.info("Poll cycle complete")


# MCP Tools — exposed via stdio JSON-RPC when invoked by an MCP host
MCP_TOOLS = [
    {
        "name": "watchdog_status",
        "description": "Get the status of all monitored hosts (last OK, drift count, remediation count)",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "watchdog_host_status",
        "description": "Get detailed status of a specific host",
        "inputSchema": {
            "type": "object",
            "properties": {"host": {"type": "string", "description": "Hostname to check"}},
            "required": ["host"],
        },
    },
    {
        "name": "watchdog_drift_history",
        "description": "Get drift history for a host over the last N hours",
        "inputSchema": {
            "type": "object",
            "properties": {
                "host": {"type": "string", "description": "Hostname"},
                "hours": {"type": "integer", "description": "Hours to look back", "default": 24},
            },
            "required": ["host"],
        },
    },
    {
        "name": "watchdog_remediate",
        "description": "Trigger manual remediation for a host",
        "inputSchema": {
            "type": "object",
            "properties": {
                "host": {"type": "string", "description": "Hostname to remediate"},
                "tags": {"type": "string", "description": "Ansible tags (comma-separated)", "default": ""},
            },
            "required": ["host"],
        },
    },
    {
        "name": "watchdog_force_ansible",
        "description": "Force run an Ansible playbook with specific tags and limit",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tags": {"type": "string", "description": "Ansible tags"},
                "limit": {"type": "string", "description": "Host limit"},
            },
        },
    },
]


def handle_mcp_tool(name: str, arguments: dict, state: StateEngine, remediation: RemediationEngine) -> dict:
    if name == "watchdog_status":
        return state.get_status()
    elif name == "watchdog_host_status":
        status = state.get_status()
        return status.get(arguments["host"], {"error": f"Host {arguments['host']} not found"})
    elif name == "watchdog_drift_history":
        audit_file = os.path.join(state.state_dir, "..", "watchdog", "audit.json")
        if os.path.exists(audit_file):
            with open(audit_file) as f:
                entries = json.load(f)
            hours = arguments.get("hours", 24)
            return {"entries": entries[-hours*12:]}
        return {"entries": []}
    elif name == "watchdog_remediate":
        host = arguments["host"]
        tags = arguments.get("tags", "")
        if remediation.can_remediate(host):
            return remediation.remediate(host, tags=tags)
        return {"error": "Cannot remediate: cooldown or max retries reached"}
    elif name == "watchdog_force_ansible":
        tags = arguments.get("tags", "")
        limit = arguments.get("limit", "")
        host = limit
        return remediation.remediate(host, tags=tags)
    else:
        return {"error": f"Unknown tool: {name}"}


def main():
    parser = argparse.ArgumentParser(description="ASIP MCP Watchdog")
    parser.add_argument("--config", "-c", default="/etc/asip/watchdog/config.yaml", help="Config file path")
    parser.add_argument("--mode", "-m", choices=["server", "poller"], default="server", help="Run mode")
    args = parser.parse_args()

    if args.mode == "server":
        run_server(args.config)
    else:
        run_poller(args.config)


if __name__ == "__main__":
    main()