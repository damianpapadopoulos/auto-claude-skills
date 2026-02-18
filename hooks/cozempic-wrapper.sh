#!/bin/bash
# cozempic-wrapper.sh — Find and run cozempic with PATH discovery
# Usage: cozempic-wrapper.sh <command> [args...]
# Exits silently (0) if cozempic is not installed.

if ! command -v cozempic >/dev/null 2>&1; then
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi

command -v cozempic >/dev/null 2>&1 && exec cozempic "$@"
exit 0
