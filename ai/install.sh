#!/usr/bin/env bash
#
# Everything the AI workspace needs, in one command.
set -euo pipefail

echo "--> the app's own dependencies, so the tests and the local run work"
python3.11 -m pip install --user --quiet \
  -r components/location-extractor/requirements-dev.txt
python3.11 -m spacy download en_core_web_md 2>&1 | tail -1

echo "--> pip-audit (queries the PyPI advisory database)"
python3.11 -m pip install --user --quiet pip-audit

echo "--> opencode (a coding agent that speaks any OpenAI-compatible endpoint)"
mkdir -p "${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
npm install -g --silent opencode-ai 2>&1 | tail -3

# No PATH juggling needed: the UDI already has ~/.local/bin and
# ~/.npm-global/bin on PATH, and both are backed by volumes in the devfile, so
# what we install here is still here after a restart.

echo
echo "Ready:"
printf '  %-14s %s\n' "pip-audit" "$(python3.11 -m pip_audit --version 2>&1 | head -1)"
printf '  %-14s %s\n' "opencode" "$(opencode --version 2>&1 | head -1 || echo 'not on PATH yet, open a new terminal')"
printf '  %-14s %s\n' "model" "${AI_MODEL:-unset} at ${OPENAI_BASE_URL:-unset}"
