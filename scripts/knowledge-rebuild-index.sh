#!/usr/bin/env bash
# knowledge-rebuild-index.sh <dir>
# Regenerate <dir>/index.md from fact-file frontmatter. Bash 3.2 compatible.
DIR="${1:?usage: knowledge-rebuild-index.sh <dir>}"
[ -d "${DIR}" ] || exit 0

_frontmatter_field() {   # <file> <field>
    awk -v f="$2" '
        NR==1 && $0=="---" {infm=1; next}
        infm && $0=="---" {exit}
        infm && $0 ~ "^"f": " {sub("^"f": ",""); print; exit}
    ' "$1"
}

TMP="$(mktemp)"
printf '<!-- schema_version: okf-0.1 -->\n# Knowledge Index\n\n' > "${TMP}"
for f in "${DIR}"/*.md; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"
    [ "${base}" = "index.md" ] && continue
    title="$(_frontmatter_field "${f}" title)"
    desc="$(_frontmatter_field "${f}" description)"
    printf '%s\t%s\t%s\n' "${base}" "${title}" "${desc}"
done | sort | while IFS="$(printf '\t')" read -r base title desc; do
    printf -- '- [%s](%s) — %s\n' "${title}" "${base}" "${desc}"
done >> "${TMP}"
mv "${TMP}" "${DIR}/index.md"
