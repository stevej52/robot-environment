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
# Install ROS 2 Jazzy Jalisco on Ubuntu 24.04 (Noble Numbat).
#
# The same script is meant to run on every machine of the robot: the x86_64
# host PC and the arm64 Jetson (JetPack 7.2 or newer, which is Ubuntu 24.04
# too). Everything comes from the official binary repository, nothing is
# compiled, so the machines end up identical. It follows
# https://docs.ros.org/en/jazzy/Installation/Ubuntu-Install-Debs.html and
# refuses to run on any other Ubuntu release: Jazzy binaries only exist for
# 24.04, and mixing releases is how you end up building from source.
#
# Run it as your normal user (it calls sudo where needed). Re-running is safe.
#
# Usage: scripts/install_ros2_jazzy.sh [options]
#   --desktop        install ros-jazzy-desktop: RViz, rqt, demos (default)
#   --base           install ros-jazzy-ros-base: no GUI tools (headless Jetson)
#   --domain-id N    put ROS_DOMAIN_ID=N in ~/.bashrc (use the same N everywhere)
#   --workspace      create ~/ros2_ws, clone ros2_pca9685 into it and build it
#   --no-upgrade     skip 'apt upgrade' before installing
#   --dry-run        print what would be done, change nothing
#   -h, --help       this text

set -euo pipefail

ROS_DISTRO_NAME=jazzy
APT_SOURCES_DEB822=${APT_SOURCES_DEB822:-/etc/apt/sources.list.d/ubuntu.sources}
APT_SOURCES_LEGACY=${APT_SOURCES_LEGACY:-/etc/apt/sources.list}
REPO_URL=https://github.com/stevej52/ros2_pca9685.git
# Used only when GitHub cannot be asked for the latest ros2-apt-source release.
FALLBACK_ROS_APT_SOURCE_VERSION=1.3.0

VARIANT=desktop
DOMAIN_ID=
WORKSPACE=false
UPGRADE=true
DRY_RUN=false
NEED_RELOGIN=false

usage() { sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --desktop) VARIANT=desktop ;;
    --base) VARIANT=ros-base ;;
    --domain-id)
      [[ $# -ge 2 && $2 =~ ^[0-9]+$ ]] || { echo "--domain-id needs a number" >&2; exit 2; }
      DOMAIN_ID=$2; shift ;;
    --domain-id=*) DOMAIN_ID=${1#*=} ;;
    --workspace) WORKSPACE=true ;;
    --no-upgrade) UPGRADE=false ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Who gets the shell setup, the i2c group and the workspace: the user who ran
# the script, also when it was started with sudo.
TARGET_USER=${SUDO_USER:-$(id -un)}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -n $TARGET_HOME ]] || die "cannot find the home directory of $TARGET_USER"

sudo_cmd() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# run_root CMD...: run a command as root (printed only with --dry-run).
run_root() {
  if $DRY_RUN; then echo "+ sudo $*"; return 0; fi
  log "sudo $*"
  sudo_cmd "$@"
}

# run_user 'shell snippet': run as the target user, in their home.
run_user() {
  if $DRY_RUN; then echo "+ ($TARGET_USER) $1"; return 0; fi
  log "($TARGET_USER) $1"
  if [[ $(id -un) == "$TARGET_USER" ]]; then
    (cd "$TARGET_HOME" && bash -c "$1")
  else
    runuser -u "$TARGET_USER" -- bash -c "cd '$TARGET_HOME' && $1"
  fi
}

# --- checks -----------------------------------------------------------------

check_platform() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
    die "this is ${PRETTY_NAME:-an unknown OS}. ROS 2 Jazzy binaries exist for Ubuntu 24.04 only; install that (docs/environment.md) instead of mixing releases."
  fi
  case $(uname -m) in
    x86_64|aarch64) ;;
    *) die "unsupported architecture $(uname -m); Jazzy is built for amd64 and arm64" ;;
  esac
  log "Ubuntu 24.04 on $(uname -m), kernel $(uname -r)"
  if [[ -f /etc/nv_tegra_release ]]; then
    log "Jetson detected: $(head -1 /etc/nv_tegra_release)"
  fi
  if $DRY_RUN; then
    log "dry run: nothing will be changed"
  elif [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    log "sudo will ask for your password"
    sudo -v
  fi
}

# --- steps ------------------------------------------------------------------

configure_locale() {
  if locale 2>/dev/null | grep -q '^LANG=.*UTF-8'; then
    log "locale is already UTF-8 ($(locale | grep '^LANG='))"
    return
  fi
  log "setting a UTF-8 locale"
  run_root apt-get install -y locales
  run_root locale-gen en_US en_US.UTF-8
  run_root update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
  export LANG=en_US.UTF-8
}

# The ROS docs warn that a 24.04 install whose apt sources list only the base
# "noble" suite gets dependency conflicts on ros-dev-tools. Make sure
# noble-updates and noble-backports are enabled.
ensure_apt_suites() {
  local f=$APT_SOURCES_DEB822
  if [[ -f $f ]]; then
    local tmp
    tmp=$(mktemp)
    awk '
      /^Suites:/ {
        n = split($0, w, " "); noble = 0; upd = 0; bp = 0
        for (i = 2; i <= n; i++) {
          if (w[i] == "noble") noble = 1
          if (w[i] == "noble-updates") upd = 1
          if (w[i] == "noble-backports") bp = 1
        }
        if (noble && !upd) $0 = $0 " noble-updates"
        if (noble && !bp) $0 = $0 " noble-backports"
      }
      { print }' "$f" > "$tmp"
    if cmp -s "$f" "$tmp"; then
      log "apt suites already include noble-updates and noble-backports"
    else
      log "adding noble-updates and noble-backports to $f (backup in $f.bak)"
      [[ -e $f.bak ]] || run_root cp "$f" "$f.bak"
      run_root install -m 644 "$tmp" "$f"
    fi
    rm -f "$tmp"
  elif [[ -f $APT_SOURCES_LEGACY ]] && grep -qE '^deb .* noble ' "$APT_SOURCES_LEGACY"; then
    if grep -qE '^deb .* noble-updates ' "$APT_SOURCES_LEGACY"; then
      log "apt sources already include noble-updates"
    else
      local base
      base=$(grep -E '^deb .* noble ' "$APT_SOURCES_LEGACY" | head -1)
      log "adding noble-updates and noble-backports to $APT_SOURCES_LEGACY"
      if $DRY_RUN; then
        echo "+ append: ${base/ noble / noble-updates }"
        echo "+ append: ${base/ noble / noble-backports }"
      else
        printf '%s\n%s\n' "${base/ noble / noble-updates }" "${base/ noble / noble-backports }" \
          | sudo_cmd tee -a "$APT_SOURCES_LEGACY" > /dev/null
      fi
    fi
  else
    warn "could not find the Ubuntu apt sources; if 'apt install ros-dev-tools' fails, enable noble-updates and noble-backports"
  fi
}

# True when every Ubuntu archive entry already lists the universe component,
# which is the case on a normal 24.04 desktop or Jetson install.
universe_enabled() {
  local file pattern
  if [[ -f $APT_SOURCES_DEB822 ]]; then
    file=$APT_SOURCES_DEB822 pattern='^Components:'
  elif [[ -f $APT_SOURCES_LEGACY ]]; then
    file=$APT_SOURCES_LEGACY pattern='^deb .* noble'
  else
    return 1
  fi
  awk -v pat="$pattern" '$0 ~ pat { n++; if ($0 !~ /universe/) missing = 1 }
                         END { exit !(n > 0 && !missing) }' "$file"
}

# apt-get update fails outright when a source that was never fetched cannot
# be reached, and only warns when an old index can be reused. Make the
# failure readable in both cases.
apt_update() {
  run_root apt-get update \
    || die "apt-get update failed: see the errors above. If packages.ros.org is the one that failed (proxy, firewall, no network?), fix that and run the script again."
}

enable_universe() {
  apt_update
  run_root apt-get install -y software-properties-common curl ca-certificates
  if universe_enabled; then
    log "the universe component is already enabled"
  else
    run_root add-apt-repository -y universe
  fi
}

# Installs the ros2-apt-source package, which carries the repository key and
# sources list and keeps them updated through apt.
add_ros2_apt_source() {
  if dpkg -s ros2-apt-source > /dev/null 2>&1; then
    log "ros2-apt-source is already installed"
    return
  fi
  local codename version url deb=/tmp/ros2-apt-source.deb
  # shellcheck disable=SC1091
  codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")
  if $DRY_RUN; then
    echo "+ curl -fL -o $deb https://github.com/ros-infrastructure/ros-apt-source/releases/download/<latest>/ros2-apt-source_<latest>.${codename}_all.deb"
    echo "+ sudo apt-get install -y $deb"
    return
  fi
  # As in the official instructions; falls back to the release page redirect
  # when the GitHub API is rate limited, and to a pinned version after that.
  version=$(curl -fsSL --max-time 30 https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest 2>/dev/null \
    | grep -F '"tag_name"' | awk -F'"' '{print $4}' || true)
  if [[ -z $version ]]; then
    version=$(curl -fsSIL --max-time 30 -o /dev/null -w '%{url_effective}' \
      https://github.com/ros-infrastructure/ros-apt-source/releases/latest 2>/dev/null \
      | sed -n 's#.*/releases/tag/##p' || true)
  fi
  if [[ -z $version ]]; then
    version=$FALLBACK_ROS_APT_SOURCE_VERSION
    warn "could not ask GitHub for the latest ros2-apt-source release, using $version"
  fi
  url="https://github.com/ros-infrastructure/ros-apt-source/releases/download/${version}/ros2-apt-source_${version}.${codename}_all.deb"
  log "installing ros2-apt-source $version"
  if curl -fL --max-time 120 -o "$deb" "$url"; then
    run_root apt-get install -y "$deb"
    rm -f "$deb"
  else
    warn "could not download $url; adding the repository key and sources list by hand instead"
    run_root mkdir -p /usr/share/keyrings
    sudo_cmd curl -fsSL --max-time 60 https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      -o /usr/share/keyrings/ros-archive-keyring.gpg
    printf 'deb [arch=%s signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu %s main\n' \
      "$(dpkg --print-architecture)" "$codename" | sudo_cmd tee /etc/apt/sources.list.d/ros2.list > /dev/null
  fi
}

install_ros2() {
  apt_update
  if ! $DRY_RUN && ! apt-cache show "ros-${ROS_DISTRO_NAME}-ros-base" > /dev/null 2>&1; then
    die "apt cannot see the ROS 2 packages: packages.ros.org was not reachable when 'apt-get update' ran (proxy, firewall, no network?). Fix that and run the script again."
  fi
  if $UPGRADE; then
    # The ROS docs recommend an upgrade first, so that ROS packages do not
    # end up mixed with older system libraries.
    run_root env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  fi
  local pkgs=(
    "ros-${ROS_DISTRO_NAME}-${VARIANT}"
    "ros-${ROS_DISTRO_NAME}-demo-nodes-cpp"   # talker/listener for the two-machine test
    "ros-${ROS_DISTRO_NAME}-demo-nodes-py"
    ros-dev-tools                             # colcon, rosdep, vcstool, compilers
    python3-pytest
    i2c-tools                                 # i2cdetect, for the PCA9685
  )
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
}

init_rosdep() {
  if [[ -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    log "rosdep is already initialised"
  else
    run_root rosdep init
  fi
  run_user "rosdep update"
}

# Lets the target user open /dev/i2c-* without sudo (see README, Requirements).
setup_i2c() {
  if ! getent group i2c > /dev/null; then
    run_root groupadd --system i2c
  fi
  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx i2c; then
    log "$TARGET_USER is already in the i2c group"
  else
    run_root usermod -aG i2c,render,video "$TARGET_USER"
    NEED_RELOGIN=true
  fi
  # Make sure the devices are actually owned by that group.
  if grep -rqsE 'i2c.*GROUP=' /etc/udev/rules.d /usr/lib/udev/rules.d /lib/udev/rules.d 2>/dev/null; then
    log "a udev rule for the i2c group already exists"
  else
    local rule=/etc/udev/rules.d/90-ros2-pca9685-i2c.rules
    log "adding $rule"
    if $DRY_RUN; then
      echo "+ write $rule: KERNEL==\"i2c-[0-9]*\", GROUP=\"i2c\", MODE=\"0660\""
    else
      echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' | sudo_cmd tee "$rule" > /dev/null
      sudo_cmd udevadm control --reload
      sudo_cmd udevadm trigger --subsystem-match=i2c-dev || true
    fi
  fi
}

# Keeps logind from deleting the user's shared memory when their last session
# ends (RemoveIPC=yes is the default). Fast DDS uses /dev/shm between nodes on
# one machine, so anything still running after an SSH logout - the robot's
# systemd service, a nohup'd simulator - lost every local topic at that moment
# while the network path to other machines kept working (robot, 2026-09-23).
setup_logind() {
  local conf=/etc/systemd/logind.conf.d/robot-removeipc.conf
  if [[ -f $conf ]]; then
    log "logind already keeps user IPC ($conf)"
    return
  fi
  log "writing $conf (RemoveIPC=no)"
  if $DRY_RUN; then
    echo "+ write $conf: [Login] RemoveIPC=no; systemctl restart systemd-logind"
  else
    sudo_cmd mkdir -p "$(dirname "$conf")"
    printf '[Login]\n# ROS 2 nodes keep running after a logout; their Fast DDS shared memory must too.\nRemoveIPC=no\n' | sudo_cmd tee "$conf" > /dev/null
    sudo_cmd systemctl restart systemd-logind
  fi
}

write_bashrc() {
  local rc="$TARGET_HOME/.bashrc" block
  block="# >>> ros2_pca9685: ROS 2 ${ROS_DISTRO_NAME} (scripts/install_ros2_jazzy.sh) >>>"
  block+=$'\n'"source /opt/ros/${ROS_DISTRO_NAME}/setup.bash"
  if [[ -n $DOMAIN_ID ]]; then
    block+=$'\n'"export ROS_DOMAIN_ID=${DOMAIN_ID}"
  fi
  if $WORKSPACE; then
    # shellcheck disable=SC2016  # $HOME is meant to be expanded by the user's shell
    block+=$'\n''[ -f "$HOME/ros2_ws/install/setup.bash" ] && source "$HOME/ros2_ws/install/setup.bash"'
  fi
  block+=$'\n'"# <<< ros2_pca9685 <<<"
  if $DRY_RUN; then
    echo "+ update $rc with:"
    echo "    ${block//$'\n'/$'\n'    }"
    return
  fi
  log "updating $rc"
  if [[ -f $rc ]] && grep -q '^# >>> ros2_pca9685' "$rc"; then
    sed -i '/^# >>> ros2_pca9685/,/^# <<< ros2_pca9685 <<</d' "$rc"
    local rest
    rest=$(cat "$rc")                # drops the trailing blank lines
    printf '%s\n' "$rest" > "$rc"
  fi
  printf '\n%s\n' "$block" >> "$rc"
  if [[ $EUID -eq 0 && $TARGET_USER != root ]]; then
    chown "$TARGET_USER" "$rc"
  fi
}

build_workspace() {
  local ws="$TARGET_HOME/ros2_ws"
  run_user "mkdir -p '$ws/src' && cd '$ws/src' && { [ -d ros2_pca9685 ] || git clone $REPO_URL; }"
  run_user "source /opt/ros/${ROS_DISTRO_NAME}/setup.bash && cd '$ws' && rosdep install --from-paths src --ignore-src -y && colcon build --symlink-install"
}

summary() {
  echo
  log "done"
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "  machine:  $(hostname), $(uname -m), ${PRETTY_NAME}, kernel $(uname -r)"
  if [[ -f /etc/nv_tegra_release ]]; then
    echo "  jetson:   $(head -1 /etc/nv_tegra_release)"
  fi
  echo "  ROS 2:    ${ROS_DISTRO_NAME} $(dpkg-query -W -f='${Version}' "ros-${ROS_DISTRO_NAME}-ros-base" 2>/dev/null || echo '(not installed: dry run?)')"
  echo "  python:   $(python3 --version 2>&1)"
  [[ -n $DOMAIN_ID ]] && echo "  domain:   ROS_DOMAIN_ID=${DOMAIN_ID}"
  $WORKSPACE && echo "  workspace: $TARGET_HOME/ros2_ws"
  echo
  echo "Open a new terminal (or run: source ~/.bashrc), then try:"
  echo "  ros2 run demo_nodes_cpp talker        # and on another machine or terminal:"
  echo "  ros2 run demo_nodes_py listener"
  if $NEED_RELOGIN; then
    echo "Log out and back in once so that the i2c group membership takes effect."
  fi
  echo "Compare machines with scripts/check_environment.sh."
}

main() {
  check_platform
  configure_locale
  ensure_apt_suites
  enable_universe
  add_ros2_apt_source
  install_ros2
  init_rosdep
  setup_i2c
  setup_logind
  write_bashrc
  if $WORKSPACE; then build_workspace; fi
  summary
}

# Only run when executed, not when sourced (which the tests do).
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main
fi
