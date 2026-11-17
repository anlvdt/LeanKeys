"""Markdown report for a webbench results file.

Usage: python3 -I tools/webbench/report.py results.jsonl

Only status "ok" cases are scored. Aborted, no-result and typist-error cases are counted
but not scored. The research group is kept out of the main totals and listed separately.
Latency is reported for human and fast speeds only.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from scoring import char_diff, percentile, word_latencies  # noqa: E402
from wordscore import word_errors  # noqa: E402

LATENCY_SPEEDS = ('human', 'fast')
STATUSES = ('ok', 'aborted', 'no-result', 'typist-error')
KEY_RE = re.compile(r'perf: key ms=([0-9.]+)')
SEND_RE = re.compile(r'perf: send bs=(\d+) len=(\d+) ms=([0-9.]+)')


def load(path):
    with open(path, encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


def _new_row():
    return {'cases': {s: 0 for s in STATUSES}, 'words': 0, 'wrong': 0, 'wrong_vn': 0,
            'wrong_en': 0, 'extra': 0, 'lost': 0, 'lat': []}


def summarize(records):
    """One row per (section, browser, field, engine, speed). section is 'main' or 'research'."""
    rows = {}
    for r in records:
        if r.get('kind') == 'perf':
            continue
        section = 'research' if r['group'] == 'research' else 'main'
        key = (section, r['browser'], r['field'], r['engine'], r['speed'])
        row = rows.setdefault(key, _new_row())
        row['cases'][r['status']] += 1
        if r['status'] != 'ok':
            continue
        words, wrong, wrong_vn, wrong_en = word_errors(r['target'], r['flags'], r['text'])
        extra, lost = char_diff(r['target'], r['text'])
        row['words'] += words
        row['wrong'] += wrong
        row['wrong_vn'] += wrong_vn
        row['wrong_en'] += wrong_en
        row['extra'] += extra
        row['lost'] += lost
        if r['speed'] in LATENCY_SPEEDS and r.get('sent') and r.get('inputs') is not None:
            row['lat'].extend(x for x in word_latencies(r['sent'], r['word_spans'], r['inputs'])
                              if x is not None)
    out = []
    for key in sorted(rows, key=lambda k: (k[0] != 'main', k[1:])):
        row = rows[key]
        row['section'], row['browser'], row['field'], row['engine'], row['speed'] = key
        out.append(row)
    return out


def perf_summary(records):
    """Per engine: p50/p95 of LeanKeys key time and send time, in ms."""
    keys, sends = {}, {}
    for r in records:
        if r.get('kind') != 'perf':
            continue
        for line in r['lines']:
            m = KEY_RE.search(line)
            if m:
                keys.setdefault(r['engine'], []).append(float(m.group(1)))
            m = SEND_RE.search(line)
            if m:
                sends.setdefault(r['engine'], []).append(float(m.group(3)))
    out = {}
    for engine in sorted(set(keys) | set(sends)):
        out[engine] = {'key': _stats(keys.get(engine, [])), 'send': _stats(sends.get(engine, []))}
    return out


def _stats(xs):
    return {'n': len(xs), 'p50': percentile(xs, 50), 'p95': percentile(xs, 95)}


def _f(x, digits=1):
    return '-' if x is None else ('%.*f' % (digits, x))


def _table(headers, lines):
    out = ['| ' + ' | '.join(headers) + ' |', '|' + '|'.join('---' for _ in headers) + '|']
    out.extend('| ' + ' | '.join(str(c) for c in ln) + ' |' for ln in lines)
    return out


def _case_row(row):
    c = row['cases']
    return '%d/%d/%d/%d' % (c['ok'], c['aborted'], c['no-result'], c['typist-error'])


def _score_lines(rows):
    lines = []
    for row in rows:
        pct = (100.0 * row['wrong'] / row['words']) if row['words'] else None
        lat = row['lat']
        lines.append([row['browser'], row['field'], row['engine'], row['speed'],
                      _case_row(row), row['words'], _f(pct), row['wrong_vn'], row['wrong_en'],
                      row['extra'], row['lost'],
                      _f(percentile(lat, 50), 0) if row['speed'] in LATENCY_SPEEDS else '-',
                      _f(percentile(lat, 95), 0) if row['speed'] in LATENCY_SPEEDS else '-'])
    return lines


HEADERS = ['Browser', 'Field', 'Engine', 'Speed', 'Cases ok/abort/no-result/typist-err',
           'Words', '% wrong', 'Wrong VN', 'Wrong EN', 'Extra', 'Lost',
           'Lat p50 ms', 'Lat p95 ms']


def render(records):
    rows = summarize(records)
    main = [r for r in rows if r['section'] == 'main']
    research = [r for r in rows if r['section'] == 'research']
    out = ['# webbench report', '', '## Scored matrix (research excluded)', '']
    out.extend(_table(HEADERS, _score_lines(main)) if main else ['No scored cases.'])
    if research:
        out += ['', '## Research group (not in totals)', '']
        out.extend(_table(HEADERS, _score_lines(research)))
    perf = perf_summary(records)
    if perf:
        out += ['', '## LeanKeys perf (debug log, ms)', '']
        out.extend(_table(['Engine', 'Key n', 'Key p50', 'Key p95', 'Send n', 'Send p50',
                           'Send p95'],
                          [[e, p['key']['n'], _f(p['key']['p50'], 3), _f(p['key']['p95'], 3),
                            p['send']['n'], _f(p['send']['p50'], 3), _f(p['send']['p95'], 3)]
                           for e, p in perf.items()]))
    return '\n'.join(out) + '\n'


def main(argv=None):
    p = argparse.ArgumentParser(description='webbench report')
    p.add_argument('results')
    args = p.parse_args(argv)
    sys.stdout.write(render(load(args.results)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
