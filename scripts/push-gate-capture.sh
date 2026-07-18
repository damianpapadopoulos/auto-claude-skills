#!/bin/bash
# push-gate-capture.sh — diagnostic subprocess for the push gate (issue #127).
# Invoked ONLY from openspec-guard.sh's EXIT trap, in a fully-redirected
# subshell. Writes ONE compact JSONL record per push/merge invocation to
# ~/.claude/.push-gate-invocation-log. Fail-open, diagnostic-only. NEVER runs
# on the guard's decision path (subprocess at EXIT). All input via PGC_* env.
# Bash 3.2 compatible.
set -u

command -v jq >/dev/null 2>&1 || exit 0   # jq-gated: diagnostic only

_dir="${HOME}/.claude"
LOG="${_dir}/.push-gate-invocation-log"
[ -d "${_dir}" ] || mkdir -p "${_dir}" 2>/dev/null || exit 0

_decision="${PGC_DECISION:-allow}"
_action="${PGC_ACTION:-unknown}"
_command="${PGC_COMMAND:-}"
_transcript="${PGC_TRANSCRIPT:-}"
_token="${PGC_SESSION_TOKEN:-}"
_guard="${PGC_GUARD_PATH:-}"
_proot="${PGC_PLUGIN_ROOT:-}"
_input="${PGC_INPUT:-}"
_err=""

# command sha/len + credential redaction (no secrets in the log)
_clen="${#_command}"
_csha="$(printf '%s' "${_command}" | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | cut -d' ' -f1)" || _csha=""
_credacted="$(printf '%s' "${_command}" \
  | sed -E 's/(^| )[A-Za-z_][A-Za-z0-9_]*=[^ ]*/\1<redacted-env>/g; s#://[^/@ ]*@#://<redacted>@#g')" || _credacted=""
[ "${PUSH_GATE_CAPTURE_FULL_CMD:-}" = "1" ] || _command=""

# drift evidence: which file ran + its cksum + plugin version
_cksum=""
[ -n "${_guard}" ] && [ -f "${_guard}" ] && _cksum="$(cksum "${_guard}" 2>/dev/null)"
_ver=""
[ -n "${_proot}" ] && [ -f "${_proot}/.claude-plugin/plugin.json" ] && \
  _ver="$(jq -r '.version // empty' "${_proot}/.claude-plugin/plugin.json" 2>/dev/null)"

# on deny only: true on-disk replay (recursion-guarded) + gate-status mirror
_replay=""; _mirror=""
case "${_decision}" in
  deny*)
    if [ -n "${_guard}" ] && [ -f "${_guard}" ]; then
      _replay="$(PUSH_GATE_CAPTURE_DISABLE=1 CLAUDE_PLUGIN_ROOT="${_proot}" bash "${_guard}" <<<"${_input}" 2>/dev/null)" || _err="replay_failed"
    fi
    if [ -n "${_proot}" ] && [ -f "${_proot}/scripts/gate-status.sh" ]; then
      _mirror="$(bash "${_proot}/scripts/gate-status.sh" 2>&1)" || _err="${_err}${_err:+;}mirror_failed"
    fi
    ;;
esac

case "${_clen}" in ''|*[!0-9]*) _clen=0 ;; esac
_line="$(jq -cn \
  --arg decision "${_decision}" --arg action "${_action}" \
  --arg guard "${_guard}" --arg cksum "${_cksum}" --arg ver "${_ver}" \
  --arg token "${_token}" --arg csha "${_csha}" --argjson clen "${_clen}" \
  --arg credacted "${_credacted}" --arg cmd "${_command}" \
  --arg transcript "${_transcript}" --arg replay "${_replay}" \
  --arg mirror "${_mirror}" --arg err "${_err}" --argjson pid "$$" \
  '{event:"exit",pid:$pid,action:$action,decision:$decision,
    guard_path:$guard,guard_cksum:$cksum,plugin_version:$ver,
    session_token:$token,command_sha:$csha,command_len:$clen,
    command_redacted:$credacted,command:$cmd,transcript_path:$transcript,
    ondisk_replay:$replay,gate_status_mirror:$mirror,
    capture_error:(if $err=="" then null else $err end)}')" || exit 0

umask 077
printf '%s\n' "${_line}" >> "${LOG}" 2>/dev/null || exit 0
chmod 0600 "${LOG}" 2>/dev/null || true

# rotate: keep last 500 if the log exceeds 1000 lines
_n="$(wc -l < "${LOG}" 2>/dev/null | tr -d ' ')"
case "${_n}" in ''|*[!0-9]*) _n=0 ;; esac
if [ "${_n}" -gt 1000 ]; then
  tail -n 500 "${LOG}" > "${LOG}.tmp" 2>/dev/null && mv "${LOG}.tmp" "${LOG}" 2>/dev/null || true
  chmod 0600 "${LOG}" 2>/dev/null || true
fi
exit 0
