#!/usr/bin/env python3
"""Fetch incidents within a time window from a GCP monitoring project.

Usage: python3 pull-incidents.py --project PROJECT_ID --days 14 --output /tmp/ah-alerts.json

Paginates automatically. Filters by open_time >= cutoff. Extracts: name, state,
openTime, closeTime, policy details, resource labels, metric type.
"""
import argparse, json, subprocess, sys, urllib.parse
from datetime import datetime, timedelta, timezone


def get_token():
    try:
        return subprocess.check_output(
            ['gcloud', 'auth', 'print-access-token'],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("ERROR: gcloud auth token unavailable.", file=sys.stderr)
        sys.exit(1)


def fetch_incidents(project, cutoff_str, token):
    all_alerts = []
    page_token = ''
    filter_str = f'open_time >= "{cutoff_str}"'
    while True:
        url = (f"https://monitoring.googleapis.com/v3/projects/{project}/alerts"
               f"?pageSize=1000&orderBy=open_time%20desc"
               f"&filter={urllib.parse.quote(filter_str)}")
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
        alerts = data.get('alerts', [])
        all_alerts.extend(alerts)
        page_token = data.get('nextPageToken', '')
        if not page_token or not alerts:
            break
    return all_alerts


def extract_alerts(alerts):
    extracted = []
    for a in alerts:
        resource = a.get('resource', {})
        res_labels = resource.get('labels', {})
        policy = a.get('policy', {})
        extracted.append({
            'name': a.get('name', ''),
            'state': a.get('state', ''),
            'openTime': a.get('openTime', ''),
            'closeTime': a.get('closeTime', ''),
            'policyName': policy.get('name', ''),
            'policyDisplayName': policy.get('displayName', ''),
            'policyLabels': policy.get('userLabels', {}),
            'resourceType': resource.get('type', ''),
            'resourceProject': res_labels.get('project_id', ''),
            'resourceLabels': res_labels,
            'metricType': a.get('metric', {}).get('type', ''),
            'conditionName': a.get('condition', {}).get('name', ''),
        })
    return extracted


def main():
    parser = argparse.ArgumentParser(description='Fetch GCP alert incidents')
    parser.add_argument('--project', required=True, help='GCP monitoring project ID')
    parser.add_argument('--days', type=int, default=14, help='Lookback window in days')
    parser.add_argument('--output', required=True, help='Output JSON file path')
    args = parser.parse_args()

    cutoff = (datetime.now(timezone.utc) - timedelta(days=args.days)).strftime('%Y-%m-%dT%H:%M:%SZ')
    token = get_token()
    alerts = fetch_incidents(args.project, cutoff, token)
    extracted = extract_alerts(alerts)
    with open(args.output, 'w') as f:
        json.dump(extracted, f, indent=2)
    print(f"Extracted {len(extracted)} incidents (since {cutoff}) to {args.output}")


if __name__ == '__main__':
    main()
