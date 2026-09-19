#!/usr/bin/env bash
# Copyright 2026 stevej52
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Print everything that has to match between the machines of the robot:
# Ubuntu release, ROS 2 distribution, Python, and the ROS environment
# variables that decide whether two machines see each other. Run it on the
# PC and on the Jetson and compare the "fingerprint" lines.
#
# Usage: scripts/check_environment.sh

set -uo pipefail

# shellcheck disable=SC1091
. /etc/os-release

row() { printf '%-12s %s\n' "$1" "$2"; }

row "host:" "$(hostname)"
row "arch:" "$(uname -m)"
row "os:" "${PRETTY_NAME:-unknown} (${VERSION_CODENAME:-?})"
row "kernel:" "$(uname -r)"

if [[ -f /etc/nv_tegra_release ]]; then
  row "jetson:" "$(head -1 /etc/nv_tegra_release)"
  if model=$(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null); then
    row "model:" "$model"
  fi
  if jp=$(dpkg-query -W -f='${Version}' nvidia-jetpack 2>/dev/null); then
    row "jetpack:" "$jp"
  else
    row "jetpack:" "nvidia-jetpack package not installed (fine unless you need CUDA)"
  fi
  if command -v nvpmodel > /dev/null; then
    row "power:" "$(sudo -n nvpmodel -q 2>/dev/null | tr '\n' ' ' || echo 'run: sudo nvpmodel -q')"
  fi
fi

row "python:" "$(python3 --version 2>&1)"

distros=()
for d in /opt/ros/*/; do
  [[ -d $d ]] || continue
  name=$(basename "$d")
  variant=ros-base
  dpkg-query -W "ros-${name}-desktop" > /dev/null 2>&1 && variant=desktop
  version=$(dpkg-query -W -f='${Version}' "ros-${name}-${variant}" 2>/dev/null || echo "?")
  distros+=("$name")
  row "ros2:" "$name (ros-${name}-${variant} $version)"
done
[[ ${#distros[@]} -gt 0 ]] || row "ros2:" "not installed (run scripts/install_ros2_jazzy.sh)"

row "ROS_DISTRO:" "${ROS_DISTRO:-not sourced in this shell}"
row "domain id:" "${ROS_DOMAIN_ID:-unset (defaults to 0)}"
row "rmw:" "${RMW_IMPLEMENTATION:-default (rmw_fastrtps_cpp)}"
row "localhost:" "ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY:-unset} (must be unset or 0 to talk to other machines)"
row "discovery:" "ROS_AUTOMATIC_DISCOVERY_RANGE=${ROS_AUTOMATIC_DISCOVERY_RANGE:-unset (defaults to SUBNET)}"
row "ip:" "$(hostname -I 2>/dev/null || echo '?')"
if command -v ufw > /dev/null; then
  row "firewall:" "$(sudo -n ufw status 2>/dev/null | head -1 || echo 'run: sudo ufw status')"
fi

shopt -s nullglob
bus_list=(/dev/i2c-*)
shopt -u nullglob
buses="${bus_list[*]}"
row "i2c:" "${buses:-no /dev/i2c-* devices}"
if id -nG | tr ' ' '\n' | grep -qx i2c; then
  row "i2c group:" "yes"
else
  row "i2c group:" "no (sudo usermod -aG i2c ${USER:-$(id -un)}, then log out and in)"
fi
if command -v i2cdetect > /dev/null && [[ -n $buses ]]; then
  i2cdetect -l 2>/dev/null | sed 's/^/             /'
fi

echo
row "fingerprint:" "${ID:-?}-${VERSION_ID:-?} $(uname -m) ros2:${distros[*]:-none} python:$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)"
