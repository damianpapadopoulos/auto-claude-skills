#!/usr/bin/env python3
"""Compute cluster statistics from alert policies and incidents.

Usage: python3 compute-clusters.py --policies P.json --alerts A.json --output C.json

Produces: cluster key normalization, episode deduplication, noise scoring,
pattern classification, label inconsistency flags.
"""
import argparse, json, re, sys
from collections import defaultdict, Counter
from datetime import datetime
from statistics import median


def parse_time(t):
    if not t:
        return None
    try:
        return datetime.strptime(t[:19], '%Y-%m-%dT%H:%M:%S')
    except ValueError:
        return None


def parse_duration_s(d):
    """Parse '300s' -> 300, '' -> 0."""
    if not d:
        return 0
    m = re.match(r'(\d+)s', d)
    return int(m.group(1)) if m else 0


def dedupe_episodes(cluster_alerts, window_sec):
    by_resource = defaultdict(list)
    for a in cluster_alerts:
        rk = json.dumps(a.get('resourceLabels', {}), sort_keys=True)
        by_resource[rk].append(a)

    total_episodes = 0
    for rk, ra in by_resource.items():
        ra.sort(key=lambda x: x.get('openTime', ''))
        episodes = 1
        last_close = parse_time(ra[0].get('closeTime', ''))
        for a in ra[1:]:
            ot = parse_time(a.get('openTime', ''))
            if ot and last_close and (ot - last_close).total_seconds() > window_sec:
                episodes += 1
            ct = parse_time(a.get('closeTime', ''))
            if ct and (last_close is None or ct > last_close):
                last_close = ct
        total_episodes += episodes
    return total_episodes, len(by_resource)


def classify_pattern(raw, episodes, durations):
    ratio = raw / max(episodes, 1)
    if ratio > 3 and raw > 10:
        return 'flapping'
    med_dur = median(durations) if durations else 0
    if episodes >= 5 and med_dur > 3600:
        return 'chronic'
    if episodes >= 5 and med_dur <= 3600:
        return 'recurring'
    if raw > 10 and episodes <= 3:
        return 'burst'
    return 'isolated'


def score_noise(raw, episodes, med_dur, med_retrig, tod_pattern):
    ratio = raw / max(episodes, 1)
    score = 0
    reasons = []
    if ratio > 5:
        score += 3; reasons.append(f"raw/episode ratio {ratio:.1f}x")
    elif ratio > 2:
        score += 1; reasons.append(f"raw/episode ratio {ratio:.1f}x")
    if med_dur is not None and med_dur < 900 and raw > 5:
        score += 2; reasons.append(f"short median duration {med_dur/60:.0f}m")
    if med_retrig is not None and 0 < med_retrig < 3600 and raw > 5:
        score += 2; reasons.append(f"retrigger every {med_retrig/60:.0f}m")
    if 'concentrated' in (tod_pattern or ''):
        m = re.search(r'h(\d+)', tod_pattern)
        if m:
            h = int(m.group(1))
            if 6 <= h <= 10 or h >= 22 or h <= 2:
                score += 1; reasons.append(f"deploy/startup-time ({tod_pattern})")
    return score, reasons


def check_label_inconsistency(policy_labels, resource_project):
    squad = policy_labels.get('squad', '')
    env = policy_labels.get('environment', '')
    staging_label = 'staging' in squad.lower() or 'test' in squad.lower() or env in ('staging', 'test')
    rp = resource_project.lower()
    # Split into segments to check for standalone 'test'/'staging' environments
    # e.g. 'test-prod' has 'prod' → still production; 'test-project' → non-prod
    segments = re.split(r'[-_.]', rp)
    prod_resource = 'prod' in rp and not (segments[-1] in ('test', 'staging') or
                                           (rp.startswith('test') and 'prod' not in segments))
    return staging_label and prod_resource


def normalize_service_name(name):
    """Normalize service name: lowercase, replace separators, strip env suffixes."""
    if not name:
        return None
    n = name.lower().replace('_', '-').replace('.', '-')
    n = re.sub(r'-(prod|staging|pta)$', '', n)
    return n or None


def extract_metric_types(policies):
    """Extract all metric types referenced in policy conditions."""
    types = set()
    for p in policies:
        for c in p.get('conditions', []):
            filt = c.get('filter', '')
            if filt:
                m = re.search(r'metric\.type\s*=\s*"([^"]+)"', filt)
                if m:
                    types.add(m.group(1))
            query = c.get('query', '')
            if query:
                m = re.match(r'([\w][\w.:/\-]+)', query.strip())
                if m and '/' in m.group(1):
                    types.add(m.group(1))
    return sorted(types)


def compute_unlabeled_ranking(policies, clusters):
    """Rank unlabeled policies by incident volume for actionable reporting."""
    policy_raw = defaultdict(int)
    policy_eps = defaultdict(int)
    for c in clusters:
        pfn = c.get('policy_full_name', '')
        policy_raw[pfn] += c.get('raw_incidents', 0)
        policy_eps[pfn] += c.get('deduped_episodes', 0)

    ranking = []
    for p in policies:
        labels = p.get('userLabels', {})
        has_owner = any(k in labels for k in ('squad', 'team', 'owner'))
        if not has_owner and p.get('enabled', True):
            pfn = p['name']
            ranking.append({
                'policy_name': p.get('displayName', ''),
                'policy_id': pfn,
                'total_raw': policy_raw.get(pfn, 0),
                'total_episodes': policy_eps.get(pfn, 0),
            })
    ranking.sort(key=lambda x: -x['total_raw'])
    return ranking[:20]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--policies', required=True)
    parser.add_argument('--alerts', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    with open(args.policies) as f:
        policies = json.load(f)
    with open(args.alerts) as f:
        alerts = json.load(f)

    # Build policy lookup for eval interval + auto_close
    # NOTE: 'duration' is hold time (condition must be true for this long).
    # 'evaluationInterval' is how often condition is checked — used for dedupe window.
    plookup = {}
    for p in policies:
        eval_interval = 0
        auto_close = parse_duration_s(p.get('autoClose', ''))
        for c in p.get('conditions', []):
            ei = c.get('evaluationInterval', '')
            if ei:
                eval_interval = max(eval_interval, parse_duration_s(ei))
        plookup[p['name']] = {
            'eval_window_sec': eval_interval,
            'auto_close_sec': auto_close,
            'userLabels': p.get('userLabels', {}),
            'notificationChannels': p.get('notificationChannels', []),
            'conditions': p.get('conditions', []),
        }

    # Build clusters
    # Key includes condition_name to avoid merging unrelated conditions
    clusters_map = defaultdict(list)
    for a in alerts:
        rp = a.get('resourceProject', 'unknown')
        pfn = a.get('policyName', 'unknown')
        mt = a.get('metricType', 'unknown')
        rt = a.get('resourceType', 'unknown')
        cn = a.get('conditionName', '')
        key = f"{rp}|{pfn}|{mt}|{rt}|{cn}"
        clusters_map[key].append(a)

    results = []
    for key, ca in clusters_map.items():
        parts = key.split('|', 4)
        rp = parts[0]

        pfn = ca[0].get('policyName', '')
        pn = ca[0].get('policyDisplayName', 'unknown')
        mt = ca[0].get('metricType', 'unknown')
        rt = ca[0].get('resourceType', 'unknown')
        pi = plookup.get(pfn, {})
        # Match condition to get threshold data
        conditions = pi.get('conditions', [])
        if len(conditions) == 1:
            matched_cond = conditions[0]
            cond_match = 'single'
        elif len(conditions) > 1:
            matched_cond = conditions[0]
            cond_match = 'ambiguous'
        else:
            matched_cond = None
            cond_match = 'none'
        dedupe_window = max(1800, 2 * pi.get('eval_window_sec', 0))

        episodes, distinct_res = dedupe_episodes(ca, dedupe_window)

        durations = []
        for a in ca:
            ot, ct = parse_time(a.get('openTime')), parse_time(a.get('closeTime'))
            if ot and ct:
                durations.append((ct - ot).total_seconds())
        med_dur = median(durations) if durations else None

        # Retrigger intervals
        by_res = defaultdict(list)
        for a in ca:
            rk = json.dumps(a.get('resourceLabels', {}), sort_keys=True)
            by_res[rk].append(a)
        retrigger = []
        for rk, ra in by_res.items():
            ra.sort(key=lambda x: x.get('openTime', ''))
            for i in range(1, len(ra)):
                po = parse_time(ra[i-1].get('openTime'))
                co = parse_time(ra[i].get('openTime'))
                if po and co:
                    retrigger.append((co - po).total_seconds())
        med_retrig = median(retrigger) if retrigger else None

        # Time of day
        hours = [parse_time(a.get('openTime')).hour for a in ca if parse_time(a.get('openTime'))]
        tod = 'unknown'
        if hours:
            hc = Counter(hours)
            peak = hc.most_common(1)[0]
            pct = peak[1] / len(hours) * 100
            tod = f"concentrated h{peak[0]:02d} ({pct:.0f}%)" if pct > 30 else "spread"

        pattern = classify_pattern(len(ca), episodes, durations)
        noise_score, noise_reasons = score_noise(len(ca), episodes, med_dur, med_retrig, tod)

        pl = ca[0].get('policyLabels', {})
        label_incon = check_label_inconsistency(pl, rp)

        results.append({
            'cluster_key': key,
            'resource_project': rp,
            'policy_name': pn,
            'metric_type': mt,
            'resource_type': rt,
            'raw_incidents': len(ca),
            'deduped_episodes': episodes,
            'dedupe_window_sec': dedupe_window,
            'distinct_resources': distinct_res,
            'median_duration_sec': med_dur,
            'median_retrigger_sec': med_retrig,
            'tod_pattern': tod,
            'pattern': pattern,
            'noise_score': noise_score,
            'noise_reasons': noise_reasons,
            'label_inconsistency': label_incon,
            'notification_channels': len(pi.get('notificationChannels', [])),
            'squad': pi.get('userLabels', {}).get('squad', '-'),
            'eval_window_sec': pi.get('eval_window_sec', 0),
            'auto_close_sec': pi.get('auto_close_sec', 0),
            'policy_full_name': pfn,
            'condition_name': ca[0].get('conditionName', ''),
            'threshold_value': matched_cond.get('thresholdValue') if matched_cond else None,
            'comparison': matched_cond.get('comparison', '') if matched_cond else '',
            'condition_filter': matched_cond.get('filter', '') if matched_cond else '',
            'condition_query': matched_cond.get('query', '') if matched_cond else '',
            'condition_type': matched_cond.get('type', '') if matched_cond else '',
            'condition_match': cond_match,
        })

    results.sort(key=lambda x: -x['raw_incidents'])
    metric_types = extract_metric_types(policies)
    unlabeled = compute_unlabeled_ranking(policies, results)
    output = {
        'clusters': results,
        'metric_types_in_inventory': metric_types,
        'unlabeled_ranking': unlabeled,
    }
    with open(args.output, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"Computed {len(results)} clusters from {len(alerts)} incidents across {len(policies)} policies")


if __name__ == '__main__':
    main()
