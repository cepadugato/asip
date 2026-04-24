import json
import logging
import os
import yaml
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from watchdog.state import StateEngine
from watchdog.remediation import RemediationEngine

logger = logging.getLogger("asip.watchdog.webhook")

state_engine: StateEngine = None
remediation_engine: RemediationEngine = None


def init_engines(state: StateEngine, remediation: RemediationEngine):
    global state_engine, remediation_engine
    state_engine = state
    remediation_engine = remediation


@asynccontextmanager
async def lifespan(app_instance: FastAPI):
    global state_engine, remediation_engine
    config_path = os.environ.get("WATCHDOG_CONFIG", "/etc/asip/watchdog/config.yaml")
    if os.path.exists(config_path):
        with open(config_path) as f:
            cfg = yaml.safe_load(f)
        state_engine = StateEngine(state_dir="/var/lib/asip/watchdog")
        remediation_cfg = cfg.get("remediation", {})
        remediation_cfg["log_dir"] = cfg.get("logging", {}).get("dir", "/var/log/watchdog")
        remediation_engine = RemediationEngine(config=remediation_cfg, state=state_engine)
        logger.info(f"Watchdog engines initialized from {config_path}")
    else:
        state_engine = StateEngine()
        logger.warning(f"Config {config_path} not found, using defaults")
    yield


app = FastAPI(title="ASIP Watchdog Webhook", version="1.0.0", lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "asip-watchdog", "version": "1.0.0"}


@app.post("/webhook/goss")
async def goss_webhook(request: Request):
    body = await request.json()
    host = body.get("host", "unknown")
    ip = body.get("ip", "unknown")
    summary = body.get("summary", {})
    failed_count = summary.get("failed-count", summary.get("failed", 0))
    failed_checks = body.get("failed_checks", [])

    logger.info(f"Webhook received: host={host}, ip={ip}, failed={failed_count}")

    if failed_count > 0:
        state_engine.record_drift(host, ip, failed_count, body)
        severity = _classify_severity(failed_count, failed_checks)
        if remediation_engine and remediation_engine.can_remediate(host):
            tags = _determine_tags(failed_checks)
            logger.info(f"Triggering remediation for {host} with tags={tags}, severity={severity}")
            result = remediation_engine.remediate(host, tags=tags)
            return {"status": "remediation_triggered", "host": host, "severity": severity, "result": result}
        else:
            logger.warning(f"Cannot remediate {host}: cooldown or max retries reached")
            return {"status": "drift_detected_no_remediation", "host": host, "severity": severity}
    else:
        state_engine.record_ok(host, ip)
        return {"status": "ok", "host": host}


@app.get("/status")
async def get_status():
    return state_engine.get_status()


@app.get("/status/{host}")
async def get_host_status(host: str):
    status = state_engine.get_status()
    return status.get(host, {"error": f"Host {host} not found"})


@app.post("/remediate/{host}")
async def manual_remediate(host: str, request: Request):
    body = await request.json() if request.headers.get("content-type") == "application/json" else {}
    tags = body.get("tags", "")
    if remediation_engine:
        result = remediation_engine.remediate(host, tags=tags)
        return {"status": "remediation_triggered", "host": host, "result": result}
    return {"error": "Remediation engine not initialized"}


def _classify_severity(failed_count: int, failed_checks: list) -> str:
    if failed_count >= 4:
        return "high"
    return "low"


def _determine_tags(failed_checks: list) -> str:
    tags = set()
    for check in failed_checks:
        check_type = check.get("type", "")
        if check_type in ("file", "command", "service"):
            resource = check.get("resource", "")
            if "sshd_config" in resource or "ssh" in resource:
                tags.add("hardening")
            elif "service" in resource:
                tags.add("service")
        if check_type == "service":
            tags.add("service")
    # Remove empty strings
    tags.discard("")
    if not tags:
        return "hardening"
    return ",".join(sorted(tags))