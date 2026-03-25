#!/usr/bin/env python3
"""Fetch all alert policies from a GCP monitoring project via REST API.

Usage: python3 pull-policies.py --project PROJECT_ID --output /tmp/ah-policies.json

Paginates automatically. Extracts inventory fields: name, displayName, enabled,
userLabels, conditions (with PromQL/MQL/threshold details), autoClose,
notificationChannels, combiner.
"""
import argparse, json, subprocess, sys, urllib.parse


def get_token():
    try:
        return subprocess.check_output(
            ['gcloud', 'auth', 'print-access-token'],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("ERROR: gcloud auth token unavailable. Run: gcloud auth login", file=sys.stderr)
        sys.exit(1)


def fetch_all_policies(project, token):
    all_policies = []
    page_token = ''
    while True:
        url = (f"https://monitoring.googleapis.com/v3/projects/{project}"
               f"/alertPolicies?pageSize=500")
        if page_token:
            url += f"&pageToken={urllib.parse.quote(page_token)}"
        result = subprocess.check_output(
            ['curl', '-s', '-H', f'Authorization: Bearer {token}', url],
            text=True
        )
        data = json.loads(result)
        if 'error' in data:
            print(f"ERROR: {data['error'].get('message', data['error'])}", file=sys.stderr)
            sys.exit(1)
        policies = data.get('alertPolicies', [])
        all_policies.extend(policies)
        page_token = data.get('nextPageToken', '')
        if not page_token:
            break
    return all_policies


def extract_inventory(policies):
    inventory = []
    for p in policies:
        conditions = []
        for c in p.get('conditions', []):
            cond = {'displayName': c.get('displayName', '')}
            for ctype in ('conditionThreshold', 'conditionPrometheusQueryLanguage',
                          'conditionMonitoringQueryLanguage', 'conditionAbsent'):
                ct = c.get(ctype)
                if ct:
                    cond['type'] = ctype
                    cond['filter'] = ct.get('filter', '')
                    cond['query'] = ct.get('query', '')
                    cond['comparison'] = ct.get('comparison', '')
                    cond['thresholdValue'] = ct.get('thresholdValue')
                    cond['duration'] = ct.get('duration', '')
                    cond['evaluationInterval'] = ct.get('evaluationInterval', '')
                    cond['aggregations'] = ct.get('aggregations', [])
                    break
            conditions.append(cond)

        inventory.append({
            'name': p.get('name', ''),
            'displayName': p.get('displayName', ''),
            'enabled': p.get('enabled', True),
            'userLabels': p.get('userLabels', {}),
            'conditions': conditions,
            'autoClose': p.get('alertStrategy', {}).get('autoClose', ''),
            'notificationChannels': p.get('notificationChannels', []),
            'combiner': p.get('combiner', ''),
        })
    return inventory


def main():
    parser = argparse.ArgumentParser(description='Fetch GCP alert policy inventory')
    parser.add_argument('--project', required=True, help='GCP monitoring project ID')
    parser.add_argument('--output', required=True, help='Output JSON file path')
    args = parser.parse_args()

    token = get_token()
    raw = fetch_all_policies(args.project, token)
    inventory = extract_inventory(raw)
    with open(args.output, 'w') as f:
        json.dump(inventory, f, indent=2)
    print(f"Extracted {len(inventory)} policies to {args.output}")


if __name__ == '__main__':
    main()
