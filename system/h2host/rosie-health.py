#!/usr/bin/env python3
"""Rosie's daily health check, written on H2-Host from what the nightly backup mirrored
(Steve, 2026-09-30: "1-3 but a daily health check").

    python3 rosie-health.py [~/rosie-backup]     -> health/YYYY-MM-DD.md and health/latest.md

Reads the last 24 hours of:
  mirror/watchdog/events.jsonl      what dropped, what came back, what was restarted, give-ups
  mirror/journal/<date>.txt         the robot's own log, warnings and the lines that matter
                                    (battery level, Wi-Fi drops, restarts, stuck sound, crashes)
  mirror/bags/drive-*/analysis/     the drives analysed since (report.txt from drive_report)
and says in a page what happened, most important first. No robot needed: it runs on the
mirror, so it can be re-run any time.
"""
import glob
import json
import os
import re
import sys
import time
from collections import Counter
from datetime import datetime, timedelta


def read(path):
    try:
        with open(path, errors='replace') as f:
            return f.read()
    except OSError:
        return ''


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
        out.append((t, os.path.basename(d), report))
    return out


def pick(report, key):
    for ln in report.splitlines():
        if ln.startswith(key):
            return ln.strip()
    return ''


def main(base):
    now = datetime.now()
    since = now - timedelta(hours=24)
    ev = events_last_day(os.path.join(base, 'mirror', 'watchdog', 'events.jsonl'), since)
    jl = journal_lines(os.path.join(base, 'mirror', 'journal'), since)
    drives = drives_last_day(os.path.join(base, 'mirror', 'bags'), since)
    have_journal = bool(jl)

    kinds = Counter(e['kind'] for e in ev)
    downs = Counter(e['what'] for e in ev if e['kind'] == 'down')
    gave_up = [e for e in ev if e['kind'] == 'gave_up']
    acts = Counter(e['what'] for e in ev if e['kind'] == 'act')
    wifi_drops = count(jl, r'CTRL-EVENT-DISCONNECTED')
    stuck_sound = count(jl, r'still \d+ active urbs|USB sound stuck')
    crashes = count(jl, r'process has died|Check failed|kernel panic|segfault')
    restarts = count(jl, r'Started jetnano-robot.service|Starting jetnano-robot.service')
    bat_lines = [ln for ln in jl if 'battery level' in ln or 'powering off' in ln.lower()]
    bat_levels = Counter(re.search(r'battery level (\w+)', ln).group(1) for ln in bat_lines
                         if re.search(r'battery level (\w+)', ln))
    hot = [ln for ln in jl if 'running hot' in ln]

    lines = [f'# Rosie health, {now:%Y-%m-%d %H:%M} (the last 24 h)', '']
    worry = []
    if gave_up:
        worry.append(f'the watchdog GAVE UP on: ' + ', '.join(sorted({e["what"] for e in gave_up})))
    if crashes:
        worry.append(f'{crashes} crash line(s) in the log')
    if stuck_sound:
        worry.append(f'USB sound stuck in the kernel ({stuck_sound} line(s)): a reboot clears it')
    if 'flat' in bat_levels:
        worry.append('the battery went FLAT (motors locked)')
    if hot:
        worry.append(f'running hot: {hot[-1].split("]: ")[-1]}')
    lines.append('## Worries' if worry else '## Worries: none')
    lines += [f'- {w}' for w in worry]
    lines.append('')

    lines.append('## Drives' + (f' ({len(drives)})' if drives else ': none'))
    for t, name, report in drives:
        if not report:
            lines.append(f'- {t:%H:%M} {name}: not analysed yet')
            continue
        first = report.splitlines()[0] if report else ''
        secs = re.search(r': (\d+) s,', first)
        lines.append(f'- {t:%H:%M} {name}: ' + (f'{secs.group(1)} s; ' if secs else '')
                     + '; '.join(x for x in (pick(report, 'EKF:'), pick(report, 'guard:'), pick(report, 'battery:')) if x))
    lines.append('')

    lines.append('## Watchdog' + (f' ({len(ev)} events)' if ev else ': quiet'))
    if downs:
        lines.append('- went down: ' + ', '.join(f'{k} x{v}' for k, v in downs.most_common()))
    if acts:
        lines.append('- restarted by it: ' + ', '.join(f'{k} x{v}' for k, v in acts.most_common()))
    if kinds.get('back'):
        lines.append(f'- came back: {kinds["back"]}')
    if kinds.get('slow'):
        lines.append(f'- ran slow: {kinds["slow"]}')
    lines.append('')

    lines.append('## System' + ('' if have_journal else ' (no journal mirrored for the day)'))
    if have_journal:
        lines.append(f'- Wi-Fi drops: {wifi_drops}')
        lines.append(f'- robot software starts: {restarts}')
        if bat_levels:
            lines.append('- battery levels seen: ' + ', '.join(f'{k} x{v}' for k, v in bat_levels.most_common()))
        if bat_lines:
            lines.append(f'- last battery line: {bat_lines[-1].split("]: ")[-1][:120]}')
    lines.append('')
    text = '\n'.join(lines) + '\n'
    out = os.path.join(base, 'health')
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, f'{now:%Y-%m-%d}.md'), 'w') as f:
        f.write(text)
    with open(os.path.join(out, 'latest.md'), 'w') as f:
        f.write(text)
    print(text)


if __name__ == '__main__':
    main(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/rosie-backup'))
