#!/usr/bin/env python3
"""
Sandbox Domain Auto-Allowlist Hook
===================================
Two-phase hook (PreToolUse + PostToolUse) for Bash tool.

PreToolUse:  Best-effort domain extraction from command string.
             If new domains found, add to allowedDomains and block (exit 2).
PostToolUse: Detect proxy timeout patterns in command output,
             extract blocked domains, add to allowedDomains.
"""

import json
import re
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"

# --- Domain extraction from command string (PreToolUse) ---

_URL_EXTRACTORS = [
    re.compile(r"https?://([\w.-]+)"),
    re.compile(r"git@([\w.-]+):"),
    re.compile(r"\w+@([\w.-]+\.\w{2,})"),
    re.compile(r"(?:--host(?:name)?|-H)\s+['\"]?([\w.-]+\.\w{2,})"),
    re.compile(r"(?:--(?:registry|endpoint|url|server|api-url))\s+https?://([\w.-]+)"),
    re.compile(
        r"\b(?:curl|wget|ping|nslookup|dig|nc|telnet|nmap|traceroute|host)"
        r"\b.*?\s([\w][\w.-]*\.\w{2,})"
    ),
]

# --- Domain extraction from output (PostToolUse) ---

_PROXY_BLOCK_INDICATORS = [
    "Connection timed out",
    "Failed reading proxy response",
    "Operation timed out",
    "Proxy CONNECT aborted",
]

_OUTPUT_DOMAIN_EXTRACTORS = [
    re.compile(r"CONNECT\s+([\w.-]+):\d+"),
    re.compile(r"--\d{4}-\d{2}-\d{2}.*?https?://([\w.-]+)"),
    re.compile(r"https?://([\w.-]+)"),
    re.compile(r"Could not resolve host:\s*([\w.-]+)"),
    re.compile(r"Failed to connect to\s+([\w.-]+)"),
]

_IGNORE_HOSTS = {"localhost", "127.0.0.1", "::1", "0.0.0.0"}


def _extract(patterns: list, text: str) -> set[str]:
    domains = set()
    for pattern in patterns:
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


def handle_pre(input_data: dict):
    command = input_data.get("tool_input", {}).get("command", "")
    if not command:
        return
    domains = _extract(_URL_EXTRACTORS, command)
    if not domains:
        return
    added = ensure_allowed(domains)
    if added:
        names = ", ".join(sorted(added))
        print(f"sandbox allowedDomains に {names} を追加しました。再実行してください。", file=sys.stderr)
        sys.exit(2)


def handle_post(input_data: dict):
    tool_response = input_data.get("tool_response", {})
    stdout = tool_response.get("stdout", "")
    stderr = tool_response.get("stderr", "")
    output = f"{stdout}\n{stderr}"

    if not any(ind in output for ind in _PROXY_BLOCK_INDICATORS):
        return

    domains = _extract(_OUTPUT_DOMAIN_EXTRACTORS, output)
    if not domains:
        return

    added = ensure_allowed(domains)
    if added:
        names = ", ".join(sorted(added))
        print(
            f"sandbox network block を検出。allowedDomains に {names} を追加しました。再実行してください。",
            file=sys.stderr,
        )


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    if input_data.get("tool_name") != "Bash":
        sys.exit(0)

    event = input_data.get("hook_event_name", "")
    if event == "PreToolUse":
        handle_pre(input_data)
    elif event == "PostToolUse":
        handle_post(input_data)

    sys.exit(0)


if __name__ == "__main__":
    main()
