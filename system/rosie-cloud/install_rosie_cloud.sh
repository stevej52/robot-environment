#!/usr/bin/env bash
# Rosie's cloud rules (Codex, 2026-10-19; merged 2026-10-21): which words may go to Claude.
#   /opt/rosie-cloud/cloud_policy.py   root:root 644 - the module brain.py and listen.py load; they
#                                      refuse it (no Claude at all) unless root owns it and its folders
#   /etc/rosie-cloud/policy.json       root:jeston 640 - "ordinary_audio": "automatic" or "local_only"
#   /etc/rosie-cloud/caller.key        root:jeston 640 - the signing key; made here once, never in git
# Run as root on Rosie: sudo bash install_rosie_cloud.sh. Then restart the brain (and listen).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
install -d -o root -g root -m 755 /opt/rosie-cloud
install -o root -g root -m 644 "$here/cloud_policy.py" /opt/rosie-cloud/cloud_policy.py
install -d -o root -g jeston -m 750 /etc/rosie-cloud
[ -f /etc/rosie-cloud/policy.json ] || install -o root -g jeston -m 640 "$here/policy.json" /etc/rosie-cloud/policy.json
if [ ! -f /etc/rosie-cloud/caller.key ]; then
    umask 077
    python3 -c 'import secrets; print(secrets.token_urlsafe(48))' > /etc/rosie-cloud/caller.key
    chown root:jeston /etc/rosie-cloud/caller.key
    chmod 640 /etc/rosie-cloud/caller.key
fi
echo "rosie-cloud installed: $(sha256sum /opt/rosie-cloud/cloud_policy.py | cut -c1-16)"
