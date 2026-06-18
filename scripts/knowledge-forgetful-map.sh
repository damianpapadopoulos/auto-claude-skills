#!/usr/bin/env bash
# knowledge-forgetful-map.sh — deterministic slug→memory_id map + content hash.
# jq optional: degrade to grep/sed when absent. Bash 3.2 compatible.
sub="${1:?hash|get|put}"; shift
case "${sub}" in
    hash) shasum "$1" 2>/dev/null | cut -d' ' -f1 ;;
    get)  m="$1"; slug="$2"
          if command -v jq >/dev/null 2>&1; then jq -r --arg s "${slug}" '.[$s].id // empty' "${m}" 2>/dev/null
          else grep -oE "\"${slug}\":[[:space:]]*\{[^}]*\"id\":[[:space:]]*[0-9]+" "${m}" 2>/dev/null | grep -oE '[0-9]+$'; fi ;;
    put)  m="$1"; slug="$2"; id="$3"; h="$4"
          if command -v jq >/dev/null 2>&1; then
              tmp="$(mktemp)"; jq --arg s "${slug}" --argjson id "${id}" --arg h "${h}" \
                  '.[$s]={id:$id,hash:$h}' "${m}" > "${tmp}" 2>/dev/null && mv "${tmp}" "${m}"
          else
              printf '{"%s":{"id":%s,"hash":"%s"}}' "${slug}" "${id}" "${h}" > "${m}"
          fi ;;
    *) exit 2 ;;
esac
