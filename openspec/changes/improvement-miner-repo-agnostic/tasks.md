# Tasks: repo-agnostic improvement-miner

> Checkpoints reference branch commits. After squash-merge they are typically
> recoverable only via the feature's GitHub PR (`gh pr view <N> --json commits`)
> — plain clones and forks do not fetch PR refs.

## Completed

- [x] 1 Frontmatter classifier + revival boolean (`json_memory_index`, `mem_type`) [checkpoint: bb76f2b]
- [x] 2 Project-noise advisory flag (`mem_noise`) [checkpoint: e797a56]
- [x] 3 Injection hardening — description length cap [checkpoint: 4ac1d75]
- [x] 4 repo_type detection + env override (`json_repo_type`) [checkpoint: 9471e1e]
- [x] 5 SKILL.md prose — report-only gate, noise/revival extraction, kill reframing [checkpoint: d441f5f]
- [x] 6 CHANGELOG + full-suite verification [checkpoint: f002045]
- [x] 7 Review fix — word-anchor noise completion markers [checkpoint: e2a433a]
