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

# npm -g installs into NPM_CONFIG_PREFIX, which is not on the default PATH.
# We append rather than override, so nothing the image set up gets lost.
BIN="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/bin"
if ! grep -q "${BIN}" "${HOME}/.bashrc" 2>/dev/null; then
  echo "export PATH=\"${BIN}:\$HOME/.local/bin:\$PATH\"" >> "${HOME}/.bashrc"
  echo "--> added ${BIN} to ~/.bashrc"
fi
export PATH="${BIN}:${HOME}/.local/bin:${PATH}"

echo
echo "Ready:"
printf '  %-14s %s\n' "pip-audit" "$(python3.11 -m pip_audit --version 2>&1 | head -1)"
printf '  %-14s %s\n' "opencode" "$(opencode --version 2>&1 | head -1 || echo 'not on PATH yet, open a new terminal')"
printf '  %-14s %s\n' "model" "${AI_MODEL:-unset} at ${OPENAI_BASE_URL:-unset}"
