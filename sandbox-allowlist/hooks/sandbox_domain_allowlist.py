#!/usr/bin/env python3
"""
Sandbox Domain Auto-Allowlist Hook (PostToolUse / PostToolUseFailure)
=====================================================================
Detect proxy timeout patterns in Bash command output and extract
blocked domains. Reports them via stderr so Claude can add them
to settings.json allowedDomains.
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
    "context deadline exceeded",
    "proxyconnect tcp",
    "blocked-by-allowlist",
    "CONNECT tunnel failed",
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


def get_allowed_domains() -> set[str]:
    try:
        settings = json.loads(SETTINGS_PATH.read_text())
        return set(settings.get("sandbox", {}).get("network", {}).get("allowedDomains", []))
    except Exception:
        return set()


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

    already_allowed = get_allowed_domains()
    new_domains = domains - already_allowed
    if new_domains:
        names = ", ".join(sorted(new_domains))
        print(
            f"sandbox network block を検出しました。"
            f"以下のドメインを settings.json の sandbox.network.allowedDomains に追加してください: {names}",
            file=sys.stderr,
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
