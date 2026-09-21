#!/usr/bin/env python3
"""Have the cluster's own model triage our dependency vulnerabilities.

pip-audit tells you which CVEs you have. It does not tell you what to do about
them in this codebase. So we hand its findings, plus the requirements file, to
a model served on OpenShift AI and ask for the patch.

The model behind LOC_EXT_AI_MODEL is DeepSeek-R1, which thinks out loud before
it answers: the interesting text arrives in 'reasoning_content' and the actual
answer in 'content'. Give it enough tokens or you get the thinking and no
answer at all.

Usage:
    python3 ai/dependency-review.py [requirements-file]
"""

import json
import os
import subprocess
import sys
import urllib.request

BASE_URL = os.getenv("OPENAI_BASE_URL", "").rstrip("/")
API_KEY = os.getenv("OPENAI_API_KEY", "")
MODEL = os.getenv("AI_MODEL", "deepseek-r1-distill-qwen-14b")

REQUIREMENTS = sys.argv[1] if len(sys.argv) > 1 else "components/location-extractor/requirements.txt"

# The model serves a 16,384 token context. A long audit with full advisory text
# blows straight past that, so we send the worst offenders and trim the prose.
MAX_FINDINGS = int(os.getenv("AI_MAX_FINDINGS", "12"))
MAX_DESCRIPTION = 240


def audit(path: str) -> list[dict]:
    """Run pip-audit and return its findings, de-duplicated."""
    print(f"--> Auditing {path}")
    result = subprocess.run(
        [sys.executable, "-m", "pip_audit", "-r", path, "-f", "json",
         "--progress-spinner", "off"],
        capture_output=True, text=True,
    )
    if not result.stdout.strip():
        print(result.stderr, file=sys.stderr)
        sys.exit("pip-audit produced no output")

    data = json.loads(result.stdout)
    seen, findings = set(), []
    for dep in data.get("dependencies", []):
        for vuln in dep.get("vulns", []):
            key = (dep["name"], vuln["id"])
            if key in seen:
                continue
            seen.add(key)
            findings.append({
                "package": dep["name"],
                "installed": dep["version"],
                "id": vuln["id"],
                "fix_versions": vuln.get("fix_versions", []),
                "description": (vuln.get("description") or "")[:MAX_DESCRIPTION],
            })
    return findings


def worst_first(findings: list[dict]) -> list[dict]:
    """Most-affected packages first, so a trim keeps the interesting ones."""
    per_package: dict[str, int] = {}
    for f in findings:
        per_package[f["package"]] = per_package.get(f["package"], 0) + 1
    return sorted(findings, key=lambda f: (-per_package[f["package"]], f["package"]))


def ask(findings: list[dict], requirements: str) -> tuple[str, str]:
    prompt = f"""You are reviewing the dependencies of a Python microservice that
runs on OpenShift. Here is its requirements.txt:

{requirements}

pip-audit reported these vulnerabilities:

{json.dumps(findings, indent=2)}

Answer three things, briefly:
1. Which pins have to change, and to exactly which versions.
2. Whether any of those bumps is likely to break a Flask 3.x application.
3. The complete corrected requirements.txt, in a code block.
"""
    body = json.dumps({
        "model": MODEL,
        "max_tokens": 3000,
        "temperature": 0.2,
        "messages": [{"role": "user", "content": prompt}],
    }).encode()

    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {API_KEY}",
                 "Content-Type": "application/json"},
    )
    print(f"--> Asking {MODEL} at {BASE_URL}")
    with urllib.request.urlopen(req, timeout=300) as resp:
        payload = json.load(resp)

    message = payload["choices"][0]["message"]
    return message.get("reasoning_content") or "", message.get("content") or ""


def main() -> None:
    if not BASE_URL or not API_KEY:
        sys.exit("OPENAI_BASE_URL and OPENAI_API_KEY are not set - is the "
                 "ice-demo-ai secret mounted into this workspace?")

    findings = audit(REQUIREMENTS)
    if not findings:
        print("\nNo known vulnerabilities. Nothing to ask the model about.")
        return

    print(f"\n{len(findings)} finding(s):\n")
    for f in findings:
        fixes = ", ".join(f["fix_versions"]) or "no fix published"
        print(f"  {f['package']} {f['installed']}  {f['id']}  -> {fixes}")

    sent = worst_first(findings)[:MAX_FINDINGS]
    if len(sent) < len(findings):
        print(f"\n(sending the {len(sent)} most relevant of {len(findings)} to the model - "
              f"its context is 16k tokens)")

    reasoning, answer = ask(sent, open(REQUIREMENTS).read())

    if reasoning:
        print("\n" + "=" * 70)
        print("How the model got there")
        print("=" * 70)
        print(reasoning.strip()[:1500])

    print("\n" + "=" * 70)
    print("What it suggests")
    print("=" * 70)
    print(answer.strip())


if __name__ == "__main__":
    main()
