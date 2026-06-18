#!/usr/bin/env bash
# knowledge-forgetful-map.sh — deterministic slug→memory_id map + content hash.
# Format: tab-separated lines <slug>\t<id>\t<hash>. No jq required. Bash 3.2 compatible.
sub="${1:?hash|get|put|del}"; shift
TAB="$(printf '\t')"
case "${sub}" in
    hash) shasum "$1" 2>/dev/null | cut -d' ' -f1 ;;
    get)  m="$1"; slug="$2"
          [ -f "${m}" ] || { exit 0; }
          awk -F'\t' -v s="${slug}" '$1==s{print $2;exit}' "${m}" ;;
    put)  m="$1"; slug="$2"; id="$3"; h="$4"
          tmp="$(mktemp)"
          if [ -f "${m}" ]; then
              grep -v "^${slug}${TAB}" "${m}" > "${tmp}" 2>/dev/null || true
          fi
          printf '%s\t%s\t%s\n' "${slug}" "${id}" "${h}" >> "${tmp}"
          mv "${tmp}" "${m}" ;;
    del)  m="$1"; slug="$2"
          [ -f "${m}" ] || { exit 0; }
          tmp="$(mktemp)"
          grep -v "^${slug}${TAB}" "${m}" > "${tmp}" 2>/dev/null || true
          mv "${tmp}" "${m}" ;;
    *) exit 2 ;;
esac
