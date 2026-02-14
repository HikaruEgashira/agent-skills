#!/usr/bin/env python3
"""
Sandbox Domain Auto-Allowlist Hook (PostToolUse only)
=====================================================
Detect proxy timeout patterns in Bash command output,
extract blocked domains, and add them to allowedDomains.
"""

import json
import re
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"

_PROXY_BLOCK_INDICATORS = [
    "Connection timed out",
    "Failed reading proxy response",
    "Operation timed out",
    "Proxy CONNECT aborted",
]

_DOMAIN_EXTRACTORS = [
    re.compile(r"CONNECT\s+([\w.-]+):\d+"),
    re.compile(r"--\d{4}-\d{2}-\d{2}.*?https?://([\w.-]+)"),
    re.compile(r"https?://([\w.-]+)"),
    re.compile(r"Could not resolve host:\s*([\w.-]+)"),
    re.compile(r"Failed to connect to\s+([\w.-]+)"),
]

_IGNORE_HOSTS = {"localhost", "127.0.0.1", "::1", "0.0.0.0"}


def extract_domains(text: str) -> set[str]:
    domains = set()
    for pattern in _DOMAIN_EXTRACTORS:
        for match in pattern.finditer(text):
            host = match.group(1).lower().rstrip(".")
            if host not in _IGNORE_HOSTS and "." in host:
                domains.add(host)
    return domains


def load_settings() -> dict:
    if SETTINGS_PATH.exists():
        return json.loads(SETTINGS_PATH.read_text())
    return {}


def save_settings(settings: dict):
    SETTINGS_PATH.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")


def ensure_allowed(domains: set[str]) -> set[str]:
    settings = load_settings()
    sandbox = settings.setdefault("sandbox", {})
    network = sandbox.setdefault("network", {})
    allowed = set(network.get("allowedDomains", []))
    new_domains = domains - allowed
    if new_domains:
        allowed.update(new_domains)
        network["allowedDomains"] = sorted(allowed)
        save_settings(settings)
    return new_domains


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    if input_data.get("tool_name") != "Bash":
        sys.exit(0)

    tool_response = input_data.get("tool_response", {})
    stdout = tool_response.get("stdout", "")
    stderr = tool_response.get("stderr", "")
    output = f"{stdout}\n{stderr}"

    if not any(ind in output for ind in _PROXY_BLOCK_INDICATORS):
        sys.exit(0)

    domains = extract_domains(output)
    if not domains:
        sys.exit(0)

    added = ensure_allowed(domains)
    if added:
        names = ", ".join(sorted(added))
        print(
            f"sandbox network block を検出。allowedDomains に {names} を追加しました。再実行してください。",
            file=sys.stderr,
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
