#!/usr/bin/env bash
# knowledge-validate.sh <dir> — validate a .claude/knowledge bundle. Bash 3.2 compatible.
DIR="${1:?usage: knowledge-validate.sh <dir>}"
[ -d "${DIR}" ] || exit 0
ERRORS=0
_err() { printf '[ERROR] %s\n' "$1" >&2; ERRORS=$((ERRORS+1)); }

_frontmatter_field() {
    awk -v f="$2" 'NR==1 && $0=="---"{infm=1;next} infm && $0=="---"{exit}
        infm && $0 ~ "^"f": "{sub("^"f": ","");print;exit}' "$1"
}

# Collect existing slugs (basename without .md), excluding index.md
SLUGS=""
for f in "${DIR}"/*.md; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"; [ "${base}" = "index.md" ] && continue
    slug="${base%.md}"
    SLUGS="${SLUGS} ${slug}"
    # type mandatory
    [ -n "$(_frontmatter_field "${f}" type)" ] || _err "${base}: missing 'type'"
    # source repo-relative path must resolve (skip URLs / PR refs / CLAUDE.md anchors)
    src="$(_frontmatter_field "${f}" source)"
    case "${src}" in
        http://*|https://*|"#"*|PR\#*|"") : ;;
        *:*) p="${src%%:*}"; [ -e "${p}" ] || _err "${base}: source path '${p}' not found" ;;
        *) case "${src}" in */*) [ -e "${src}" ] || _err "${base}: source path '${src}' not found";; esac ;;
    esac
    # dangling [[slug]] links
    for ref in $(grep -oE '\[\[[a-z0-9-]+\]\]' "${f}" | sed 's/\[\[//;s/\]\]//'); do
        case " ${SLUGS} ${ref} " in *" ${ref} "*) : ;; esac
        [ -e "${DIR}/${ref}.md" ] || _err "${base}: dangling link [[${ref}]]"
    done
done

# index.md ↔ disk: every fact appears in index
if [ -e "${DIR}/index.md" ]; then
    for slug in ${SLUGS}; do
        grep -qF "(${slug}.md)" "${DIR}/index.md" || _err "index.md missing entry for ${slug}.md"
    done
fi

[ "${ERRORS}" -eq 0 ] || exit 1
