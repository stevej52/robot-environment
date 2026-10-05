#!/usr/bin/env bash
# Rosie's Wi-Fi on the in-kernel rtw88 driver instead of Realtek's out-of-tree rtl8822ce
# (2026-10-04). Run on the Jetson; re-run after any kernel update (the modules are built for
# the running kernel).
#
# Why: all four kernel deaths of 2026-10-04 came within 0-6 s of the vendor driver hopping
# channels or reconnecting on a weak signal. rtw88 is the driver for the same RTL8822CE chip
# that lives in the Linux tree; NVIDIA's kernel does not build it, so it is built here from
# the matching kernel.org sources and installed under /lib/modules/<kernel>/updates/rtw88.
#
# What it does:
#   1. fetches drivers/net/wireless/realtek/rtw88 of the kernel's own version (sparse clone)
#   2. builds rtw88_core, rtw88_pci, rtw88_8822c, rtw88_8822ce against the installed headers
#   3. installs them, depmod
#   4. decompresses the chip firmware: Ubuntu ships rtw8822c_fw.bin.zst, the tegra kernel has
#      no compressed-firmware loader (CONFIG_FW_LOADER_COMPRESS unset): "failed to load firmware"
#   5. installs the blacklist of the vendor module + the rtw88 options, and the boot check
#      rosie-wifi-fallback (back to the vendor driver if rtw88 does not get her online in 90 s)
#
# Gotcha: switching drivers LIVE leaves wpa_supplicant holding the old interface and scans
# jam ("Reject scan trigger since one is already pending"): switch with a reboot.
set -euo pipefail
K=$(uname -r)
V=$(grep -E "^(VERSION|PATCHLEVEL|SUBLEVEL) =" /lib/modules/$K/build/Makefile | awk '{print $3}' | paste -sd.)
ENV_SYS="$(cd "$(dirname "$0")/.." && pwd)/system"
SRC=$HOME/src/linux-rtw-v$V
echo "kernel $K, sources v$V"
if [ ! -d "$SRC/drivers/net/wireless/realtek/rtw88" ]; then
    git clone -q --depth 1 --branch "v$V" --filter=blob:none --sparse \
        https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$SRC"
    git -C "$SRC" sparse-checkout set drivers/net/wireless/realtek/rtw88
fi
D=$SRC/drivers/net/wireless/realtek/rtw88
make -C /lib/modules/$K/build M=$D CONFIG_RTW88=m CONFIG_RTW88_CORE=m CONFIG_RTW88_PCI=m \
    CONFIG_RTW88_8822C=m CONFIG_RTW88_8822CE=m \
    KCFLAGS="-DCONFIG_RTW88_8822C_MODULE -DCONFIG_RTW88_8822CE_MODULE" -j"$(nproc)" modules
sudo mkdir -p /lib/modules/$K/updates/rtw88
sudo install -m 644 $D/rtw88_core.ko $D/rtw88_pci.ko $D/rtw88_8822c.ko $D/rtw88_8822ce.ko /lib/modules/$K/updates/rtw88/
sudo depmod -a
for f in rtw8822c_fw rtw8822c_wow_fw; do
    [ -f /lib/firmware/rtw88/$f.bin ] || sudo zstd -q -d -f /lib/firmware/rtw88/$f.bin.zst -o /lib/firmware/rtw88/$f.bin
done
sudo install -m 644 "$ENV_SYS"/modprobe-rosie-wifi-driver.conf /etc/modprobe.d/rosie-wifi-driver.conf
sudo install -m 644 "$ENV_SYS"/modprobe-rosie-wifi-regdom.conf /etc/modprobe.d/rosie-wifi-regdom.conf
sudo install -m 755 "$ENV_SYS"/rosie-wifi-fallback /usr/local/sbin/rosie-wifi-fallback
sudo install -m 644 "$ENV_SYS"/rosie-wifi-fallback.service /etc/systemd/system/rosie-wifi-fallback.service
sudo systemctl daemon-reload
sudo systemctl enable rosie-wifi-fallback.service
modprobe --show-depends rtw88_8822ce
echo "done: reboot to switch (the fall-back puts the vendor driver back if rtw88 fails)"
