#!/usr/bin/env bash
# Everything on the robot that is NOT in git, in one archive, for a backup:
#
#   bash scripts/backup_robot_state.sh [out.tar.zst]      (on the robot)
#
# The house map, drive recordings, her sounds, the voice models, the
# watchdog and spending logs, the Isaac ROS workspace, the system settings
# that live outside the repositories, and an inventory of what is installed
# (apt packages, the Python venvs, Docker images, JetPack). Secrets are left
# out: the API key in /etc/default/jetnano-robot is replaced by a marker and
# NetworkManager's Wi-Fi files (they hold the password) are not copied - only
# which networks exist. Restore notes: robot-environment REBUILD.md.
set -euo pipefail
OUT=${1:-/tmp/rosie-robot-state-$(date +%Y%m%d).tar.zst}
STAGE=$(mktemp -d /tmp/rosie-backup.XXXXXX)
trap 'sudo rm -rf "$STAGE"' EXIT
H=/home/jeston

mkdir -p "$STAGE/home" "$STAGE/etc" "$STAGE/inventory"
for d in maps bags sounds voice watchdog workspaces; do
    [ -e "$H/$d" ] && cp -a "$H/$d" "$STAGE/home/"
done

# system settings outside git
sudo sed 's/^ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=(removed - make a new key, see REBUILD.md)/' \
    /etc/default/jetnano-robot > "$STAGE/etc/default-jetnano-robot"
for f in /etc/systemd/system/jetnano-robot.service /etc/systemd/system/jetnano-slam.service \
         /etc/systemd/system/isaac-vo.service /etc/systemd/system/jetson-clocks.service \
         /etc/systemd/system/wifi-watchdog.service /etc/udev/rules.d/99-robot-sensors.rules \
         /etc/systemd/logind.conf.d/robot-power-button.conf /etc/systemd/logind.conf.d/robot-removeipc.conf \
         /etc/docker/daemon.json /etc/sudoers.d/90-nopasswd-sudo; do
    [ -e "$f" ] && sudo cp "$f" "$STAGE/etc/$(echo "$f" | tr / _ | sed 's/^_//')"
done
nmcli -t -f NAME,TYPE,AUTOCONNECT connection show > "$STAGE/inventory/network-connections.txt" 2>/dev/null || true
nmcli -f 802-11-wireless.bssid,802-11-wireless.channel,802-11-wireless.band connection show \
    "$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2 ~ /wireless/ {print $1; exit}')" \
    >> "$STAGE/inventory/network-connections.txt" 2>/dev/null || true

# what is installed
head -1 /etc/nv_tegra_release > "$STAGE/inventory/jetpack.txt" || true
nvpmodel -q >> "$STAGE/inventory/jetpack.txt" 2>/dev/null || true
uname -a >> "$STAGE/inventory/jetpack.txt"
dpkg --get-selections > "$STAGE/inventory/apt-packages.txt"
apt-mark showmanual > "$STAGE/inventory/apt-manual.txt"
for v in venv-voice venv-sensors venv-tools; do
    [ -x "$H/$v/bin/pip" ] && "$H/$v/bin/pip" freeze > "$STAGE/inventory/pip-$v.txt" 2>/dev/null || true
done
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' > "$STAGE/inventory/docker-images.txt" 2>/dev/null || true
systemctl list-unit-files 'jetnano-*' isaac-vo.service jetson-clocks.service wifi-watchdog.service \
    > "$STAGE/inventory/services.txt" 2>/dev/null || true
for r in "$H"/ros2_ws/src/* "$H/robot-environment"; do
    [ -d "$r/.git" ] && echo "$(basename "$r") $(git -C "$r" rev-parse HEAD)" >> "$STAGE/inventory/git-commits.txt"
done

sudo chown -R "$(id -u):$(id -g)" "$STAGE"
tar -C "$STAGE" -cf - . | zstd -T2 -6 -q -o "$OUT" -f
echo "$OUT $(du -h "$OUT" | cut -f1)"
