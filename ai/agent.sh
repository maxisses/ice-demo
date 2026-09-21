#!/usr/bin/env bash
#
# Starts opencode against the model served on OpenShift AI.
#
# opencode wants a provider definition rather than bare OPENAI_* variables, so
# we write one from the environment the workspace already has. The endpoint is
# OpenAI-compatible, which is why a model called deepseek can sit behind a
# provider called openai.
set -euo pipefail

: "${OPENAI_BASE_URL:?not set - is the ice-demo-ai secret mounted?}"
: "${OPENAI_API_KEY:?not set - is the ice-demo-ai secret mounted?}"
MODEL="${AI_MODEL:-deepseek-r1-distill-qwen-14b}"

# opencode asks for 32000 output tokens by default. This model tops out at a
# 16384 token total, so without these limits every request is rejected before
# it reaches the GPU.
CONTEXT="${AI_CONTEXT_TOKENS:-16384}"
OUTPUT="${AI_OUTPUT_TOKENS:-6000}"

CONFIG_DIR="${HOME}/.config/opencode"
mkdir -p "${CONFIG_DIR}"

cat > "${CONFIG_DIR}/opencode.json" <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "openshift-ai": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "OpenShift AI (MaaS)",
      "options": {
        "baseURL": "${OPENAI_BASE_URL}",
        "apiKey": "${OPENAI_API_KEY}"
      },
      "models": {
        "${MODEL}": {
          "name": "${MODEL}",
          "limit": { "context": ${CONTEXT}, "output": ${OUTPUT} }
        }
      }
    }
  },
  "model": "openshift-ai/${MODEL}"
}
JSON

echo "--> opencode configured against ${OPENAI_BASE_URL} (${MODEL})"
exec opencode
