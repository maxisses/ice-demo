#!/usr/bin/env bash
#
# Everything the AI workspace needs, in one command.
set -euo pipefail

echo "--> pip-audit (queries the PyPI advisory database)"
python3.11 -m pip install --user --quiet pip-audit

echo "--> opencode (a coding agent that speaks any OpenAI-compatible endpoint)"
mkdir -p "${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
npm install -g --silent opencode-ai 2>&1 | tail -3

echo
echo "Ready:"
printf '  %-14s %s\n' "pip-audit" "$(python3.11 -m pip_audit --version 2>&1 | head -1)"
printf '  %-14s %s\n' "opencode" "$(opencode --version 2>&1 | head -1 || echo 'not on PATH yet, open a new terminal')"
printf '  %-14s %s\n' "model" "${AI_MODEL:-unset} at ${OPENAI_BASE_URL:-unset}"
