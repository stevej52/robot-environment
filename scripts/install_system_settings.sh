#!/usr/bin/env bash
# The robot's system settings that no other install script writes:
#
#   bash scripts/install_system_settings.sh            (on the Jetson)
#
#   /etc/docker/daemon.json      nvidia as Docker's default runtime, so the
#                                isaac_vo container gets the GPU however it is
#                                started (it refused to start at boot under
#                                runc, 2026-09-24)
#   /etc/systemd/logind.conf.d/robot-power-button.conf
#                                the case's power button shuts down even though
#                                no one is logged in to answer the dialog
#   /etc/firmware/nvidia/ga10b   a real copy of the GPU firmware, and
#   /etc/apt/apt.conf.d/99-rosie-etc-firmware  that refreshes it after every
#                                package change. JetPack 7.2's kernel command
#                                line looks in /etc/firmware first, which the
#                                installer never creates; the fallback through
#                                the /lib symlink failed with ELOOP on 2 of 31
#                                boots and the GPU never started (2026-09-23 and
#                                -26; NVIDIA-AI-IOT/jetson-ai-lab issue #427)
#   rosie-poweron.service + /usr/local/sbin/rosie-poweron + /usr/local/share/rosie/poweron.wav
#                                her power-on sound, as soon as the speaker
#                                exists at boot (needs ~/sounds/on1.wav)
#   /usr/lib/systemd/system-shutdown/rosie-goodbye + /usr/local/share/rosie/shutdown.wav
#                                her powering-down sound, played by systemd
#                                after everything else has stopped (needs
#                                ~/sounds/off1.wav from make_voice first)
#   /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env
#                                the boot-time GPU description (CDI spec) is
#                                always generated in Jetson (csv) mode; auto
#                                sometimes chose nvml and wrote none
#   /etc/apt/preferences.d/05-rosie-ros-packages-from-ros.pref
#                                NVIDIA's Isaac ROS apt repo (pinned at 600)
#                                ships forks of ros-jazzy-* packages versioned
#                                99.0.0 (ros-jazzy-launch, 2026-09-26) meant for
#                                its containers; this keeps the host's ROS from
#                                packages.ros.org
#   no Firefox / Thunderbird     their snaps (and the gnome, gtk and mesa snaps
#                                only they used) plus the apt placeholders that
#                                reinstall them; snap auto-refresh held, so snapd
#                                does not download and swap snaps mid-drive
#                                (1.5 GB, 2026-09-27; headless robot)
#   ModemManager disabled        no modem, but it probes every new USB serial
#                                device - the lidar's adapter among them
#   no power saving (2026-09-28, the board drew the same 9.4-9.5 W with all of it off):
#   nvme_core.default_ps_max_latency_us=0 on every APPEND line of
#                                /boot/extlinux/extlinux.conf: the SSD's own power
#                                states (APST) off. One boot stalled ~25 s on
#                                "nvme ... I/O tag ... timeout, completion polled"
#                                (a missed interrupt; 1 of 38 boots). Backup kept
#                                as extlinux.conf.before-nvme-apst-off
#   usbcore.autosuspend=-1 on every APPEND line: no USB device ever autosuspends.
#                                The RealSense is set back to "auto" by the kernel
#                                whenever the camera pipeline opens or closes it
#                                (after any udev rule has run); with the delay at -1
#                                it still never suspends (runtime_suspended_time 0)
#   /etc/udev/rules.d/99-rosie-no-autosuspend.rules
#                                every USB and PCI device kept awake (runtime PM on)
#   sleep/suspend/hibernate targets masked: a robot that suspends is a dead robot
#   (GPU engine power gating off: jetson-clocks.service, installed with the units;
#   PCIe ASPM was already off on every link, CPU idle states off by jetson_clocks,
#   Wi-Fi power save off by NetworkManager)
#
# RemoveIPC=no (logind) is written by install_ros2_jazzy.sh; the services by
# install_isaac_ros_46.sh --units. Password-free sudo for the robot's user is
# a choice this repository does not make for you - see REBUILD.md.
#
# Changes take effect at the next boot (restarting logind or Docker by hand
# ends desktop sessions and running containers).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)

if [ ! -f /etc/docker/daemon.json ]; then
    sudo install -D -m 644 "$HERE/system/docker-daemon.json" /etc/docker/daemon.json
    echo "Docker: nvidia is the default runtime (after a reboot or: sudo systemctl restart docker)"
elif grep -q '"default-runtime": "nvidia"' /etc/docker/daemon.json; then
    echo "Docker: /etc/docker/daemon.json already makes nvidia the default runtime: left as it is"
else
    echo "/etc/docker/daemon.json exists with other settings: merge $HERE/system/docker-daemon.json by hand"
fi
sudo install -D -m 644 "$HERE/system/logind-robot-power-button.conf" /etc/systemd/logind.conf.d/robot-power-button.conf
echo "logind: power button shuts down (after a reboot)"
sudo mkdir -p /etc/firmware/nvidia
sudo cp -a /usr/lib/firmware/nvidia/ga10b /etc/firmware/nvidia/
sudo install -D -m 644 "$HERE/system/apt-99-rosie-etc-firmware" /etc/apt/apt.conf.d/99-rosie-etc-firmware
echo "GPU firmware: real copy in /etc/firmware, refreshed after every apt run (used from the next boot)"
sudo install -D -m 644 "$HERE/system/nvidia-cdi-refresh.env" /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env
echo "CDI spec: always generated in csv (Jetson) mode (from the next boot)"
sudo install -D -m 644 "$HERE/system/apt-05-rosie-ros-packages-from-ros.pref" /etc/apt/preferences.d/05-rosie-ros-packages-from-ros.pref
echo "apt: the host's ROS packages always come from packages.ros.org, never NVIDIA's 99.0.0 forks"
sudo install -D -m 755 "$HERE/system/rosie-goodbye" /usr/lib/systemd/system-shutdown/rosie-goodbye
if [ -f "$HOME/sounds/off1.wav" ]; then
    sudo install -D -m 644 "$HOME/sounds/off1.wav" /usr/local/share/rosie/shutdown.wav
    echo "shutdown sound: installed (the last thing she does before the power goes)"
else
    echo "shutdown sound: hook installed, but ~/sounds/off1.wav is missing - run make_voice ~/sounds, then this again"
fi
sudo install -D -m 755 "$HERE/system/rosie-poweron" /usr/local/sbin/rosie-poweron
sudo install -D -m 644 "$HERE/system/rosie-poweron.service" /etc/systemd/system/rosie-poweron.service
if [ -f "$HOME/sounds/on1.wav" ]; then
    sudo install -D -m 644 "$HOME/sounds/on1.wav" /usr/local/share/rosie/poweron.wav
    sudo systemctl daemon-reload && sudo systemctl enable -q rosie-poweron.service
    echo "power-on sound: installed and enabled (plays as soon as the speaker exists at boot)"
else
    echo "power-on sound: unit installed but ~/sounds/on1.wav is missing - run make_voice ~/sounds, then this again"
fi
for s in firefox thunderbird gnome-46-2404 gtk-common-themes mesa-2404; do
    if snap list "$s" >/dev/null 2>&1; then sudo snap remove "$s"; fi
done
for p in firefox thunderbird; do
    if dpkg -s "$p" >/dev/null 2>&1; then sudo apt-get remove -y "$p"; fi
done
sudo snap refresh --hold >/dev/null
echo "snaps: no desktop apps, auto-refresh held"
if systemctl is-enabled -q ModemManager 2>/dev/null; then
    sudo systemctl disable --now ModemManager
fi
echo "ModemManager: disabled (no modem; it probes USB serial devices)"
EXT=/boot/extlinux/extlinux.conf
if [ -f "$EXT" ] && ! grep -q 'usbcore.autosuspend' "$EXT"; then
    sudo cp -a "$EXT" "$EXT.before-usb-autosuspend-off"
    sudo sed -i -E '/^\s*APPEND /s/$/ usbcore.autosuspend=-1/' "$EXT"
    echo "USB autosuspend: never, from the next boot (backup: $EXT.before-usb-autosuspend-off)"
fi
if [ -f "$EXT" ] && ! grep -q 'nvme_core.default_ps_max_latency_us' "$EXT"; then
    sudo cp -a "$EXT" "$EXT.before-nvme-apst-off"
    sudo sed -i -E '/^\s*APPEND /s/$/ nvme_core.default_ps_max_latency_us=0/' "$EXT"
    echo "SSD power states (APST): off from the next boot (backup: $EXT.before-nvme-apst-off)"
else
    echo "SSD power states (APST): already off in $EXT (or no extlinux.conf)"
fi
sudo install -D -m 644 "$HERE/system/udev-99-rosie-no-autosuspend.rules" /etc/udev/rules.d/99-rosie-no-autosuspend.rules
sudo rm -f /etc/udev/rules.d/50-rosie-no-autosuspend.rules      # the first name ran too early
sudo udevadm control --reload
echo "USB and PCI devices: kept awake (udev rule; plugged-in devices from now, all from the next boot)"
sudo systemctl mask -q sleep.target suspend.target hibernate.target hybrid-sleep.target
echo "sleep, suspend and hibernate: masked"

sudo install -D -m 644 "$HERE/system/sysctl-90-rosie-panic.conf" /etc/sysctl.d/90-rosie-panic.conf
sudo sysctl -q -p /etc/sysctl.d/90-rosie-panic.conf
echo "kernel crash: reboot after 5 s (kernel.panic = 5, panic_on_oops = 1)"
# zz-: after JetPack's watchdog.conf (120 s), so this one wins
sudo install -D -m 644 "$HERE/system/systemd-watchdog-rosie.conf" /etc/systemd/system.conf.d/zz-rosie-watchdog.conf
sudo systemctl daemon-reexec
echo "hardware watchdog: 20 s (a hang that cannot panic resets her in 20 s, was 2 min)"

sudo install -D -m 644 "$HERE/system/udev-99-rosie-respeaker.rules" /etc/udev/rules.d/99-rosie-respeaker.rules
sudo udevadm control --reload && sudo udevadm trigger --attr-match=idVendor=2886
echo "reSpeaker: its USB control interface open to plugdev (direction of arrival, speech detection)"

# dnsmasq came with the base image (2025-07-02) and nothing uses it; its service failed at every
# boot ("port 53: Address already in use" - systemd-resolved has it). Off (2026-09-29).
sudo systemctl disable --now dnsmasq.service 2>/dev/null || true
echo "dnsmasq: disabled (unused; it only failed at boot)"
# isc-dhcp-server: the same story; NVIDIA's USB-C networking (l4t-usb-device-mode) runs its own dhcpd
# with its own config and pid file, so the system service only failed at boot.
sudo systemctl disable --now isc-dhcp-server.service isc-dhcp-server6.service 2>/dev/null || true
echo "isc-dhcp-server services: disabled (USB-C networking starts its own dhcpd)"

sudo install -D -m 644 "$HERE/system/journald-rosie.conf" /etc/systemd/journald.conf.d/zz-rosie.conf
sudo systemctl restart systemd-journald
echo "journal: up to 2000 files (was 100, and each boot's start was deleted to stay under it)"

sudo install -D -m 755 "$HERE/system/rosie-clock" /usr/local/sbin/rosie-clock
for u in rosie-clock.service rosie-clock-rtc.service rosie-clock-save.service rosie-clock-save.timer; do
    sudo install -D -m 644 "$HERE/system/$u" "/etc/systemd/system/$u"
done
sudo systemctl daemon-reload
sudo systemctl enable --now rosie-clock.service rosie-clock-save.timer
# ... and again when the PMIC RTC driver loads and resets the clock to 1970 (~11 s in)
sudo install -D -m 644 "$HERE/system/udev-99-rosie-clock.rules" /etc/udev/rules.d/99-rosie-clock.rules
sudo udevadm control --reload
sudo /usr/local/sbin/rosie-clock save
echo "clock: the last saved time at boot instead of 1970 (saved every 10 min and at shutdown; NTP corrects it)"

# 40-pin header pin 7 as a GPIO output: the safety relay on the PCA9685's OE (ros2_pca9685
# output_enable_pin). JetPack leaves every header GPIO pad tristated (input only), so the
# pin needs this overlay, appended to the DEFAULT boot entry's OVERLAYS (from the next boot).
dtc -@ -q -I dts -O dtb -o /tmp/rosie-hdr40-pin7-output.dtbo "$HERE/system/rosie-hdr40-pin7-output.dts"
sudo install -m 644 /tmp/rosie-hdr40-pin7-output.dtbo /boot/rosie-hdr40-pin7-output.dtbo
EXT=/boot/extlinux/extlinux.conf
if ! grep -q "rosie-hdr40-pin7-output.dtbo" "$EXT"; then
    sudo cp -a "$EXT" "$EXT.before-rosie-pin7"
    sudo python3 - "$EXT" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path).read().split('
')
default = next(l.split()[1] for l in lines if l.startswith('DEFAULT'))
start = next(i for i, l in enumerate(lines) if l.strip() == f'LABEL {default}')
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('LABEL')), len(lines))
dtbo = '/boot/rosie-hdr40-pin7-output.dtbo'
for i in range(start, end):
    if lines[i].strip().startswith('OVERLAYS'):
        lines[i] = lines[i].rstrip() + ',' + dtbo
        break
else:
    fdt = next(i for i in range(start, end) if lines[i].strip().startswith('FDT'))
    lines.insert(fdt + 1, '	OVERLAYS ' + dtbo)
open(path, 'w').write('
'.join(lines))
PY
fi
echo "header pin 7: a GPIO output (overlay in the $(grep ^DEFAULT $EXT | cut -d' ' -f2) boot entry; from the next boot)"

