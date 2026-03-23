#!/usr/bin/env bash
# skills/incident-analysis/scripts/redact-evidence.sh
# Sanitizes evidence payloads before they are written to the evidence bundle.
# Reads stdin, writes sanitized output to stdout.
# Bash 3.2 compatible (macOS /bin/bash). No external deps beyond sed.

# ---------------------------------------------------------------------------
# Pattern order matters: most-specific patterns first to avoid partial matches.
# ---------------------------------------------------------------------------

sed -E \
    -e 's/eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED]/g' \
    -e 's/Bearer [A-Za-z0-9._~+\/-]+=*/Bearer [REDACTED]/g' \
    -e 's/Authorization:[[:space:]]+.+/Authorization: [REDACTED]/g' \
    -e 's/(X-Api-Key:[[:space:]]+).+/\1[REDACTED]/g' \
    -e 's/(api_key=)[^[:space:]&]+/\1[REDACTED]/g' \
    -e 's/Cookie:[[:space:]]+.+/Cookie: [REDACTED]/g' \
    -e 's/(session=)[^[:space:];,&]+/\1[REDACTED]/g' \
    -e 's/([A-Z_]*(SECRET|PASSWORD|TOKEN|KEY)=).+/\1[REDACTED]/g' \
    -e 's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/[REDACTED]/g' \
    -e 's/([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}/[REDACTED]/g' \
    -e 's/([^0-9.]|^)([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)/\1[REDACTED]\3/g'
