#!/usr/bin/env bash
# Everything on the robot that is NOT in git, in one archive, for a backup:
#
#   bash scripts/backup_robot_state.sh [out.tar.zst]      (on the robot)
#   SKIP_BAGS='drive-20260928-*' bash scripts/backup_robot_state.sh   (recordings saved elsewhere already)
#
# The house map, drive recordings, her sounds, the voice models and voice prints,
# the watchdog and spending logs, the Isaac ROS workspace, the mic's firmware
# files, the benchmark and audit notes, the system settings that live outside
# the repositories, and an inventory of what is installed (apt packages, the
# Python venvs, Docker images, JetPack). Secrets are left out: every line in
# /etc/default/jetnano-robot whose name has KEY, TOKEN, SECRET or PASS in it is
# replaced by a marker, and NetworkManager's Wi-Fi files (they hold the password)
# are not copied - only which networks exist. Restore notes: REBUILD.md.
set -euo pipefail
OUT=${1:-/tmp/rosie-robot-state-$(date +%Y%m%d).tar.zst}
STAGE=$(mktemp -d /tmp/rosie-backup.XXXXXX)
trap 'sudo rm -rf "$STAGE"' EXIT
H=/home/jeston

mkdir -p "$STAGE/home" "$STAGE/etc" "$STAGE/inventory"
for d in maps maps3d sounds voice watchdog workspaces respeaker audit calibration nav_logs tools; do
    [ -e "$H/$d" ] && cp -a "$H/$d" "$STAGE/home/"
done
if [ -d "$H/bags" ]; then
    if [ -n "${SKIP_BAGS:-}" ]; then
        rsync -a --exclude="$SKIP_BAGS" "$H/bags" "$STAGE/home/"
        echo "left out of bags/ (saved elsewhere): $SKIP_BAGS" > "$STAGE/inventory/bags-left-out.txt"
    else
        cp -a "$H/bags" "$STAGE/home/"
    fi
fi

# system settings outside git
sudo sed -E 's/^([A-Za-z_]*(KEY|TOKEN|SECRET|PASS)[A-Za-z_]*)=.*/\1=(removed - make a new one, see REBUILD.md)/I' \
    /etc/default/jetnano-robot > "$STAGE/etc/default-jetnano-robot"
for f in /etc/systemd/system/jetnano-*.service /etc/systemd/system/rosie-*.service \
         /etc/systemd/system/rosie-*.timer /etc/systemd/system/isaac-vo.service \
         /etc/systemd/system/jetson-clocks.service /etc/systemd/system/wifi-watchdog.service \
         /etc/udev/rules.d/99-robot-*.rules /etc/udev/rules.d/99-rosie-*.rules \
         /etc/systemd/journald.conf.d/*rosie*.conf /etc/sysctl.d/*rosie*.conf /usr/local/sbin/rosie-* \
         /etc/systemd/logind.conf.d/robot-power-button.conf /etc/systemd/logind.conf.d/robot-removeipc.conf \
         /boot/extlinux/extlinux.conf /etc/docker/daemon.json /etc/sudoers.d/90-nopasswd-sudo; do
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
systemctl list-unit-files 'jetnano-*' 'rosie-*' isaac-vo.service jetson-clocks.service wifi-watchdog.service \
    > "$STAGE/inventory/services.txt" 2>/dev/null || true
for r in "$H"/ros2_ws/src/* "$H/robot-environment"; do
    [ -d "$r/.git" ] && echo "$(basename "$r") $(git -C "$r" rev-parse HEAD)" >> "$STAGE/inventory/git-commits.txt"
done

sudo chown -R "$(id -u):$(id -g)" "$STAGE"
tar -C "$STAGE" -cf - . | zstd -T2 -6 -q -o "$OUT" -f
echo "$OUT $(du -h "$OUT" | cut -f1)"
