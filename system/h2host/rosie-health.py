#!/usr/bin/env python3
"""Rosie's health page, written on H2-Host from what was pulled from her
(Steve, 2026-09-30: "1-3 but a daily health check" / "I thought the page was like a web page").

    python3 rosie-health.py [~/rosie-backup]
        -> health/index.html      the page: http://192.168.1.238:8087/  (rosie-web.service)
           health/latest.md       the same in text, for ssh
           health/YYYY-MM-DD.md   the day's copies, linked from the page
           health/YYYY-MM-DD.html

Runs after every drive pull (rosie-drives, every 15 minutes) and after the nightly backup,
so drives and watchdog events are never more than 15 minutes behind; the journal is the
nightly pull's. Reads the last 24 hours of:
  mirror/watchdog/events.jsonl      what dropped, what came back, what was restarted, give-ups,
                                    the system lines (memory low, running hot)
  mirror/journal/<date>.txt         the robot's own log: battery level, Wi-Fi drops, restarts,
                                    stuck sound, crashes
  mirror/bags/drive-*/analysis/     the drives analysed since (report.txt and summary.md)
No robot needed: it runs on the mirror, so it can be re-run any time.
"""
import glob
import html
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timedelta

PORT = 8087


def read(path):
    try:
        with open(path, errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def mtime(path):
    try:
        return datetime.fromtimestamp(os.path.getmtime(path))
    except OSError:
        return None


def events_last_day(path, since):
    out = []
    for line in read(path).splitlines():
        try:
            rec = json.loads(line)
            t = datetime.strptime(rec['t'], '%Y-%m-%d %H:%M:%S')
        except (ValueError, KeyError):
            continue
        if t >= since:
            out.append(rec)
    return out


def journal_lines(folder, since):
    """Every journal line the nightly pull saved for the last day (one file per day)."""
    lines = []
    for day in (since.date(), (since + timedelta(days=1)).date()):
        lines += read(os.path.join(folder, f'{day}.txt')).splitlines()
    return lines


def count(lines, pattern):
    return sum(1 for ln in lines if re.search(pattern, ln))


def drives_last_day(bags_dir, since):
    out = []
    for d in sorted(glob.glob(os.path.join(bags_dir, 'drive-*'))):
        if d.endswith('-extra') or not os.path.isdir(d):
            continue                                   # the -extra folders and the .log files beside the bags
        m = re.search(r'drive-(\d{8})-(\d{6})', d)
        if not m:
            continue
        try:
            t = datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S')
        except ValueError:
            continue
        if t < since:
            continue
        report = read(os.path.join(d, 'analysis', 'report.txt')) or read(os.path.join(d, 'report.txt'))
        summary = read(os.path.join(d, 'analysis', 'summary.md'))
        out.append((t, os.path.basename(d), report, summary))
    return out


def pick(report, key):
    for ln in report.splitlines():
        if ln.startswith(key):
            return ln.strip()
    return ''


def drive_line(t, name, report):
    """One line per drive: length, then the EKF, guard and battery lines of drive_report."""
    if not report:
        return f'{t:%H:%M} {name}: not analysed yet'
    first = report.splitlines()[0] if report else ''
    secs = re.search(r': (\d+) s,', first)
    length = f'{int(secs.group(1)) // 60} min; ' if secs else ''
    parts = [x for x in (pick(report, 'EKF:'), pick(report, 'guard:'), pick(report, 'battery:')) if x]
    return f'{t:%H:%M} {name}: ' + length + '; '.join(parts)


def collect(base, now):
    since = now - timedelta(hours=24)
    ev_path = os.path.join(base, 'mirror', 'watchdog', 'events.jsonl')
    ev = events_last_day(ev_path, since)
    jl = journal_lines(os.path.join(base, 'mirror', 'journal'), since)
    drives = drives_last_day(os.path.join(base, 'mirror', 'bags'), since)
    journal_files = glob.glob(os.path.join(base, 'mirror', 'journal', '*.txt'))

    kinds = Counter(e['kind'] for e in ev)
    downs = Counter(e['what'] for e in ev if e['kind'] == 'down')
    gave_up = [e for e in ev if e['kind'] == 'gave_up']
    acts = Counter(e['what'] for e in ev if e['kind'] == 'act')
    system = [e for e in ev if e['kind'] == 'system']
    wifi_drops = count(jl, r'CTRL-EVENT-DISCONNECTED')
    stuck_sound = count(jl, r'still \d+ active urbs|USB sound stuck')
    crashes = count(jl, r'process has died|Check failed|kernel panic|segfault')
    restarts = count(jl, r'Started jetnano-robot.service|Starting jetnano-robot.service')
    bat_lines = [ln for ln in jl if 'battery level' in ln or 'powering off' in ln.lower()]
    bat_levels = Counter(re.search(r'battery level (\w+)', ln).group(1) for ln in bat_lines
                         if re.search(r'battery level (\w+)', ln))
    hot = [ln for ln in jl if 'running hot' in ln]
    mem_low = [e for e in system if 'memory low' in e.get('detail', '')]

    worry = []
    if gave_up:
        worry.append('the watchdog GAVE UP on: ' + ', '.join(sorted({e['what'] for e in gave_up})))
    if mem_low:
        worry.append(f'memory ran low {len(mem_low)} time(s), last {mem_low[-1]["t"][11:16]}: {mem_low[-1]["detail"]}')
    if crashes:
        worry.append(f'{crashes} crash line(s) in the log')
    if stuck_sound:
        worry.append(f'USB sound stuck in the kernel ({stuck_sound} line(s)): a reboot clears it')
    if 'flat' in bat_levels:
        worry.append('the battery went FLAT (motors locked)')
    if hot:
        worry.append(f'running hot: {hot[-1].split("]: ")[-1]}')
    other_system = [e for e in system if e not in mem_low]
    for e in other_system[-3:]:
        worry.append(f'{e["t"][11:16]} {e["detail"]}')

    watchdog = []
    if downs:
        watchdog.append('went down: ' + ', '.join(f'{k} x{v}' for k, v in downs.most_common()))
    if acts:
        watchdog.append('restarted by it: ' + ', '.join(f'{k} x{v}' for k, v in acts.most_common()))
    if kinds.get('back'):
        watchdog.append(f'came back: {kinds["back"]}')
    if kinds.get('slow'):
        watchdog.append(f'ran slow: {kinds["slow"]}')

    system_lines = []
    if jl:
        system_lines.append(f'Wi-Fi drops: {wifi_drops}')
        system_lines.append(f'robot software starts: {restarts}')
        if bat_levels:
            system_lines.append('battery levels seen: ' + ', '.join(f'{k} x{v}' for k, v in bat_levels.most_common()))
        if bat_lines:
            system_lines.append(f'last battery line: {bat_lines[-1].split("]: ")[-1][:120]}')

    last_pull = read(os.path.join(base, 'last-pull.txt')).strip()
    return {
        'now': now, 'worry': worry, 'drives': drives, 'n_events': len(ev), 'watchdog': watchdog,
        'system': system_lines, 'have_journal': bool(jl),
        'events_at': mtime(ev_path),
        'journal_at': max((mtime(p) for p in journal_files), default=None) if journal_files else None,
        'last_pull': last_pull,
    }


def to_markdown(h):
    lines = [f'# Rosie health, {h["now"]:%Y-%m-%d %H:%M} (the last 24 h)', '']
    lines.append('## Worries' if h['worry'] else '## Worries: none')
    lines += [f'- {w}' for w in h['worry']]
    lines.append('')
    lines.append('## Drives' + (f' ({len(h["drives"])})' if h['drives'] else ': none'))
    lines += [f'- {drive_line(t, name, report)}' for t, name, report, _ in h['drives']]
    lines.append('')
    lines.append('## Watchdog' + (f' ({h["n_events"]} events)' if h['n_events'] else ': quiet'))
    lines += [f'- {w}' for w in h['watchdog']]
    lines.append('')
    lines.append('## System' + ('' if h['have_journal'] else ' (no journal mirrored for the day)'))
    lines += [f'- {s}' for s in h['system']]
    lines.append('')
    if h['last_pull']:
        lines.append(f'_{h["last_pull"]}_')
        lines.append('')
    return '\n'.join(lines) + '\n'


STYLE = """
body { font-family: -apple-system, Segoe UI, Helvetica, Arial, sans-serif; max-width: 62em; margin: 1.5em auto; padding: 0 1em; color: #222; line-height: 1.45; }
h1 { font-size: 1.5em; margin-bottom: 0.2em; } h2 { font-size: 1.15em; margin-top: 1.4em; border-bottom: 1px solid #ddd; }
.stamp { color: #666; font-size: 0.9em; }
.worry { background: #fdecea; border-left: 6px solid #c62828; padding: 0.6em 1em; margin: 0.6em 0; }
.fine  { background: #e8f5e9; border-left: 6px solid #2e7d32; padding: 0.6em 1em; margin: 0.6em 0; }
ul { padding-left: 1.3em; } li { margin: 0.25em 0; }
details { margin: 0.35em 0; } summary { cursor: pointer; }
pre { background: #f5f5f5; padding: 0.8em; overflow-x: auto; font-size: 0.85em; white-space: pre-wrap; }
.foot { color: #666; font-size: 0.85em; margin-top: 2em; border-top: 1px solid #ddd; padding-top: 0.6em; }
"""


def to_html(h, days):
    e = html.escape
    out = ['<!doctype html><html lang="en"><head><meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width, initial-scale=1">',
           '<meta http-equiv="refresh" content="300">',
           f'<title>Rosie health {h["now"]:%Y-%m-%d}</title><style>{STYLE}</style></head><body>',
           f'<h1>Rosie health</h1><div class="stamp">{h["now"]:%A %Y-%m-%d %H:%M}, the last 24 hours</div>']
    if h['worry']:
        out.append('<h2>Worries</h2><div class="worry"><ul>' + ''.join(f'<li>{e(w)}</li>' for w in h['worry']) + '</ul></div>')
    else:
        out.append('<h2>Worries</h2><div class="fine">None. Nothing gave up, no crash lines, memory and sound fine, battery never flat.</div>')

    out.append('<h2>Drives' + (f' ({len(h["drives"])})' if h['drives'] else '') + '</h2>')
    if not h['drives']:
        out.append('<p>No recordings in the last 24 hours.</p>')
    for t, name, report, summary in h['drives']:
        line = e(drive_line(t, name, report))
        if summary:
            out.append(f'<details><summary>{line}</summary><pre>{e(summary)}</pre></details>')
        else:
            out.append(f'<div>{line}</div>')

    out.append('<h2>Watchdog' + (f' ({h["n_events"]} events)' if h['n_events'] else ': quiet') + '</h2>')
    if h['watchdog']:
        out.append('<ul>' + ''.join(f'<li>{e(w)}</li>' for w in h['watchdog']) + '</ul>')
    out.append('<h2>System' + ('' if h['have_journal'] else ' (no journal mirrored for the day)') + '</h2>')
    if h['system']:
        out.append('<ul>' + ''.join(f'<li>{e(s)}</li>' for s in h['system']) + '</ul>')

    foot = []
    if h['last_pull']:
        foot.append(e(h['last_pull']))
    if h['events_at']:
        foot.append(f'watchdog events as of {h["events_at"]:%H:%M}')
    if h['journal_at']:
        foot.append(f'journal as of the nightly pull, {h["journal_at"]:%Y-%m-%d %H:%M}')
    foot.append('drives are pulled and analysed here on H2-Host within minutes of ending (never while she is recording); '
                'the page refreshes itself every 5 minutes')
    if days:
        foot.append('earlier days: ' + ', '.join(f'<a href="{d}.html">{d}</a>' for d in days))
    out.append('<div class="foot">' + '<br>'.join(foot) + '</div></body></html>')
    return '\n'.join(out) + '\n'


def main(base):
    now = datetime.now()
    h = collect(base, now)
    out = os.path.join(base, 'health')
    os.makedirs(out, exist_ok=True)
    today = f'{now:%Y-%m-%d}'
    days = sorted({os.path.basename(p)[:-5] for p in glob.glob(os.path.join(out, '????-??-??.html'))} | {today},
                  reverse=True)[:14]
    text = to_markdown(h)
    page = to_html(h, [d for d in days if d != today])
    for name, body in ((f'{today}.md', text), ('latest.md', text), (f'{today}.html', page), ('index.html', page)):
        with open(os.path.join(out, name), 'w') as f:
            f.write(body)
    print(text, end='')


if __name__ == '__main__':
    main(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/rosie-backup'))
