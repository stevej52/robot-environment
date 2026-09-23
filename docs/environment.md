# One environment for the whole robot: Ubuntu 24.04 + ROS 2 Jazzy

This is the plan for setting up the host PC (and a spare PC to rehearse on)
and the NVIDIA Jetson Orin Nano Super Developer Kit so that every machine
runs **the same Ubuntu release and the same ROS 2 distribution, installed
from binary packages**. Minimal source builds, none to start with, and no
version juggling.

Last checked: September 2026. The Ubuntu and ROS 2 facts below were checked
against the vendors' own files (the Ubuntu checksum list, the ROS 2
documentation sources, REP-2000). The NVIDIA facts come from NVIDIA's pages
as quoted in search results, not from the pages themselves, which is why
section 5 asks you to read NVIDIA's Quick Start once before flashing.

## 1. The versions, and why these

| Machine | OS | ROS 2 | Comes from |
|---|---|---|---|
| Jetson Orin Nano Super Developer Kit | **JetPack 7.2.1** = Jetson Linux 39.2.1 = **Ubuntu 24.04 LTS** (kernel 6.8, CUDA 13.2.1) | **Jazzy Jalisco** (arm64, Tier 1) | NVIDIA's Jetson ISO, then `apt` |
| Host PC, spare PC | **Ubuntu 24.04.5 LTS** desktop (kernel 7.0 HWE) | **Jazzy Jalisco** (amd64, Tier 1) | Ubuntu ISO, then `apt` |

The Jetson decides. JetPack 7.2 (June 2026) was the first JetPack 7 release
to support the Orin family, and it moved the Orin Nano from Ubuntu 22.04 to
Ubuntu 24.04. JetPack 7.2.1 (August 2026) is the current one. ROS 2 is built
per Ubuntu release, so the PC has to run 24.04 as well, and both machines
get Jazzy:

- **Jazzy Jalisco** is the LTS for Ubuntu 24.04, supported until May 2029.
  NVIDIA's own Isaac ROS 4.6 also targets Jazzy on JetPack 7.2, so the
  Jetson side is squarely on it.
- **Kilted Kaiju** also runs on 24.04 but is a short release, end of life
  at the end of 2026. Skip it.
- **Lyrical Luth** (May 2026, LTS to 2031) is built for Ubuntu **26.04** and
  has no 24.04 packages (24.04 is a Tier 3, build-from-source platform for
  it). The PC could run it; the Jetson cannot. Putting it on the PC would
  mean a different Ubuntu and a different ROS 2 on each machine, which is
  exactly the situation to avoid. Move both machines to 26.04 + Lyrical
  together, once NVIDIA ships a JetPack built on 26.04.

House rules that keep the machines identical:

- Never run `do-release-upgrade` on either machine.
- Never add the Kilted or Rolling repositories.
- Everything ROS comes from `apt` (`ros-jazzy-*`), Python packages from
  `apt` (`python3-*`) too. No `pip install` into the system Python; Ubuntu
  24.04 refuses it anyway.
- Binaries first, source builds as a deliberate exception. Start from `apt`
  every time. Build from source only when no binary does the job, and then
  decide it on purpose: check the build dependencies and what a rebuild
  costs on the Jetson, keep it to the one package that needs it, do it the
  same way on both machines, and write down here why. A source build that
  nobody wrote down is the version juggling this page exists to avoid.
- Install with the same script, `scripts/install_ros2_jazzy.sh`, on every
  machine and compare them with `scripts/check_environment.sh`.

## 2. What goes on the USB drives

You need two things, and they cannot share one stick:

| Stick | For | Image | Size |
|---|---|---|---|
| A | host PC and spare PC | `ubuntu-24.04.5.1-desktop-amd64.iso` | 8 GB or more (the image is 5.8 GB) |
| B | Jetson | Jetson ISO for JetPack 7.2.1 (Jetson Orin Nano Developer Kit) | 16 GB or more, per NVIDIA |

One stick can be reused: install the PCs from it first, then rewrite it with
the Jetson ISO.

### Stick A: Ubuntu 24.04.5 desktop

1. Download from <https://releases.ubuntu.com/24.04/>. Take
   **`ubuntu-24.04.5.1-desktop-amd64.iso`**. The original `24.04.5` desktop
   image was pulled a few days after release because its installer crashed on
   the "extended" package selection; `24.04.5.1` is the fixed respin. Do not
   use an older 24.04.5 desktop image you may already have.
2. Check the download. From the same page, `SHA256SUMS` says:

   ```
   4da4a0c9035da8e68a59a838674f403f0a54472c78a83b4fb7f78d03588f85a7 *ubuntu-24.04.5.1-desktop-amd64.iso
   ```

   ```bash
   # Linux / macOS
   sha256sum ubuntu-24.04.5.1-desktop-amd64.iso
   # Windows (PowerShell)
   Get-FileHash .\ubuntu-24.04.5.1-desktop-amd64.iso -Algorithm SHA256
   ```

3. Write it to the stick. Anything on the stick is erased.
   - **Windows / macOS / Linux**: [balenaEtcher](https://etcher.balena.io/),
     choose the ISO, choose the stick, flash.
   - **Windows**: [Rufus](https://rufus.ie/) also works. Keep the default
     "ISO image mode" when it asks.
   - **Linux command line**:

     ```bash
     lsblk                                   # find the stick, e.g. /dev/sdb: NOT your system disk
     sudo dd if=ubuntu-24.04.5.1-desktop-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync
     ```

ROS 2 cannot be baked into the Ubuntu installer stick, and does not need to
be: after the first boot it is one command (section 3, step 4). If you want
the scripts on a stick anyway, copy the `scripts/` folder of this repository
to any second stick, or to the Jetson stick's leftover space after writing
it. They are also one `git clone` away.

### Stick B: the Jetson ISO

Since JetPack 7.2 there is **no SD-card image** for the Orin Nano Developer
Kit any more. Instead you write NVIDIA's "Jetson ISO" to a USB stick, boot
the Jetson from it, and the installer puts Jetson Linux on the storage
attached to the kit (NVMe SSD or microSD).

1. Download the Jetson Orin Nano Developer Kit ISO for JetPack 7.2.1 from
   <https://developer.nvidia.com/embedded/jetpack/downloads> (NVIDIA
   developer account required, free).
2. Write it to a 16 GB or larger stick with balenaEtcher or `dd`, exactly as
   above. Do **not** write it to a microSD card; it is an installer, not a
   disk image.

### Storage for the Jetson

The developer kit ships without storage. Get an **NVMe SSD (M.2 2280)** for
the slot under the module; NVIDIA suggests 256 GB or more. A microSD card
is still accepted as the installer target, but NVIDIA steers everyone to
NVMe now and there are forum reports of trouble installing 7.2 to microSD.
Fit the SSD before the first boot.

## 3. Rehearse on the spare computer

Do the whole thing on the spare PC first. It costs an hour and turns the
real host install into a repeat.

1. **Boot from stick A.** Plug it in, power on, press the boot-menu key
   (F12, F2, Esc or Del depending on the maker) and pick the stick. Choose
   "Try or Install Ubuntu".
2. **Install.** Interactive installation, "Default selection" of apps,
   tick "Install third-party software for graphics and Wi-Fi hardware and
   additional media formats", "Erase disk and install Ubuntu" (it is a robot
   host; give it the whole disk), no disk encryption, create your user, pick
   the time zone. If Secure Boot is on and you ticked third-party software,
   the installer asks for a one-time password; on the blue "MOK management"
   screen at the next boot choose "Enroll MOK" and type it.
3. **First boot.** Connect to the network, then bring the system up to date
   and reboot:

   ```bash
   sudo apt update && sudo apt full-upgrade -y && sudo reboot
   ```

4. **Install ROS 2 Jazzy** with the script from this repository. With
   `--workspace` it also creates `~/ros2_ws`, clones the `ros2_pca9685`
   driver into it and builds it:

   ```bash
   sudo apt install -y git
   git clone https://github.com/stevej52/robot-environment.git ~/robot-environment
   ~/robot-environment/scripts/install_ros2_jazzy.sh --domain-id 7 --workspace
   ```

   Pick any domain ID from 0 to 101 and **use the same number on every
   machine**; it is what separates your robot from other ROS 2 traffic on the
   network. The script:

   - refuses to run on anything but Ubuntu 24.04,
   - follows the official Jazzy instructions (locale, universe, the
     `ros2-apt-source` package, `apt upgrade`, `ros-jazzy-desktop`,
     `ros-dev-tools`), with `--base` for a GUI-less install,
   - initialises `rosdep`, adds you to the `i2c` group and installs
     `i2c-tools` for the PCA9685,
   - adds `source /opt/ros/jazzy/setup.bash` and the domain ID to `~/.bashrc`,
   - with `--workspace`, builds `~/ros2_ws` with this package in it.

   `--dry-run` prints what it would do. Running it again is harmless.

5. **Check.** Open a new terminal:

   ```bash
   ros2 run demo_nodes_cpp talker          # terminal 1
   ros2 run demo_nodes_py listener         # terminal 2: "I heard: Hello World"
   ros2 run ros2_pca9685 pca9685_node --ros-args --params-file ~/ros2_ws/src/ros2_pca9685/config/rc_car.yaml -p simulate:=true
   ```

   The last one runs this driver without hardware; every command it would
   send to the chip is logged instead.

## 4. The host PC when it arrives

Same stick, same steps, same script, same `--domain-id`. Then do the
two-machine test with the spare PC while both are on the same network,
preferably wired:

```bash
# on the spare PC
ros2 run demo_nodes_cpp talker
# on the host
ros2 node list                          # shows /talker
ros2 run demo_nodes_py listener         # hears it
```

If they cannot see each other, run `scripts/check_environment.sh` on both
and compare: same domain ID, `ROS_LOCALHOST_ONLY` unset, firewall inactive
(`sudo ufw status`), both on the same subnet. Wi-Fi access points sometimes
drop the multicast packets discovery relies on; a wired link is the quick
way to rule that out. The same test later proves the Jetson is on the
network correctly.

## 5. The Jetson Orin Nano Super

NVIDIA reworks this procedure with every JetPack release, so read the current
[Quick Start Guide](https://docs.nvidia.com/jetson/orin-nano-devkit/user-guide/latest/quick_start.html)
once before you begin. The steps below match the 7.2.x guide as of
September 2026. The host PC is not needed for this route at all.

### 5.1 Before you start

- NVMe SSD fitted (section 2), stick B written.
- A monitor on the **DisplayPort** output (the kit has no HDMI; a DP-to-HDMI
  adapter works), a USB keyboard and mouse, wired Ethernet.
- **Firmware check.** NVIDIA's Quick Start says JetPack 7.2 and later need
  the JetPack 6.x generation of UEFI/QSPI firmware on the kit, and that some
  kits left the factory with firmware that cannot boot the 7.2.1 installer.
  JetPack 6 is Jetson Linux 36.x, so 36 is the number to look for. To see
  yours: power on with no storage and no stick,
  press `Esc` when the NVIDIA logo appears, and read the firmware version
  line near the top of the UEFI screen. Anything 36.x or newer: carry on. A
  35.x kit (old stock, JetPack 5 era) must first go through NVIDIA's
  [JetPack 6.x update path](https://docs.nvidia.com/jetson/orin-nano-devkit/user-guide/latest/update_firmware.html)
  before it can boot the 7.2.1 installer.

### 5.2 Install

1. Plug stick B into a USB port, power on. The kit boots the installer from
   the stick by itself. If it does not, press `Esc` at the NVIDIA logo, open
   **Boot Manager** and pick the stick.
2. If the installer finds older QSPI firmware it offers a UEFI capsule
   update with a 30 second countdown: press `Y`. **The countdown defaults
   to skipping the update.** Look away for half a minute and the install
   carries on onto mismatched firmware, which is the worst thing that can
   happen at this step: the kit boots, looks healthy, and the graphical
   first-boot wizard shows nothing but a blinking cursor, so **no user
   account is ever created and there is no way in**. The USB-C serial
   console cannot rescue it (section 7). The only fix is to boot stick B
   again and press `Y` this time. To check afterwards, compare the version
   on the UEFI screen with `cat /etc/nv_tegra_release`: the GCIDs must
   match. Seen on 2026-09-17 with firmware `36.4.7-gcid-42132812` under a
   rootfs built from GCID `46758480`.

   The board reboots one or more times during the update. **Do not power it off** while this is going
   on. (There is an NVIDIA forum thread on kits that looped here; if yours
   does, that thread is the place to start:
   [reboot loop during the 7.2 firmware update](https://forums.developer.nvidia.com/t/jetson-orin-nano-super-8gb-stuck-in-reboot-loop-during-jetpack-7-2-iso-firmware-update-uefi-capsule-update-fails/373852).)
3. Choose the storage target: **NVMe** (or SD Card if you went that way).
   The 7.2.1 installer may not offer the OEM configuration choice at all --
   in September 2026 it went straight to the storage target -- so do not
   wait for that prompt. Then wait: white
   text scrolls for several minutes, and the kit reboots into the new system.
   The 7.2.1 ISO flashes the Orin Nano with the **Super mode** configuration
   by default.
4. First boot runs the usual Ubuntu setup ("oem-config"): licence, language,
   keyboard, user account, network. Use the same user name as on the PCs
   if you like; it makes `ssh` and file copies simpler.

Alternative route if the ISO gives trouble: NVIDIA SDK Manager on the host PC
(Ubuntu 24.04 works as the SDK Manager host, and 2.4.0 added Windows hosts)
with the kit in recovery mode over its USB-C port, "Direct Flash" to the NVMe.
That route is also how you recover a kit that no longer boots.

### 5.3 After the first boot

```bash
sudo apt update && sudo apt full-upgrade -y && sudo reboot
cat /etc/nv_tegra_release            # R39 (release), REVISION: 2.1 ...
lsb_release -a                       # Ubuntu 24.04
```

Only if you need CUDA, TensorRT and the rest of JetPack (this driver does
not, Isaac ROS does), install the meta package:

```bash
sudo apt install -y nvidia-jetpack
```

Then ROS 2, with the very same script and domain ID as on the PCs:

```bash
sudo apt install -y git
git clone https://github.com/stevej52/robot-environment.git ~/robot-environment
~/robot-environment/scripts/install_ros2_jazzy.sh --domain-id 7 --workspace
```

Use `--base` instead of the default desktop set if the Jetson will never
have a screen attached; RViz and rqt are then run on the host and talk to
the Jetson over the network. Log out and in once for the `i2c` group. Then
the two-machine test from section 4, this time Jetson against host.

### 5.4 Wiring the PCA9685 to the Orin Nano

The 40-pin header is Raspberry Pi compatible for this purpose:

| PCA9685 | Orin Nano header pin |
|---|---|
| VCC | 1 (3.3 V) |
| SDA | 3 |
| SCL | 5 |
| GND | 6 |
| V+ | separate servo supply, ground shared with the kit |

The Linux bus number is the one thing that differs from a Raspberry Pi. On
JetPack 5 and 6 the pins 3/5 bus was `/dev/i2c-7` and the pins 27/28 bus was
`/dev/i2c-1`; JetPack 7 uses a newer kernel and device tree, so check rather
than assume:

```bash
i2cdetect -l                          # lists the buses with their names
i2cdetect -y -r 7                     # the PCA9685 shows up as 40 (and 70)
```

Put the bus that shows `40` into `i2c_bus` in your parameter file. The
README's Troubleshooting section has the rest.

## 6. Keeping the two machines the same afterwards

- Update both at the same time: `sudo apt update && sudo apt full-upgrade`.
  On the Jetson this also pulls NVIDIA's own updates to Jetson Linux, which
  is what you want.
- Before installing anything new, ask whether it is an `apt` package for
  both architectures. `ros-jazzy-*` and `python3-*` packages are. Something
  that only exists on PyPI is a sign to look for another way first (a venv
  outside the ROS workspace if it must be). If a source build really is the
  answer, that is allowed: on both machines, and recorded here.
- `scripts/check_environment.sh` prints a one-line fingerprint of each
  machine; they should match except for the architecture.
- When something needs a newer Ubuntu, that is a project: both machines,
  same weekend, after NVIDIA has a JetPack for it.

## 7. If something does not work

- **`install_ros2_jazzy.sh` stops with "this is Ubuntu ..."**: it is doing
  its job. Only 24.04 gets Jazzy binaries.
- **`ros-dev-tools` has unmet dependencies**: the apt sources list only the
  base `noble` suite. The script adds `noble-updates` and `noble-backports`
  to `/etc/apt/sources.list.d/ubuntu.sources`; check that file if it was
  edited by hand.
- **GitHub API rate limit while fetching `ros2-apt-source`**: the script
  falls back to the release page, then to a pinned version, then to adding
  the key and sources list by hand.
- **`apt cannot see the ROS 2 packages`**: `packages.ros.org` was not
  reachable when the script ran `apt-get update` (proxy, firewall, no
  network). Fix the connection and run the script again; it picks up where
  it left off.
- **Two machines do not see each other**: section 4.
- **Jetson does not boot from the stick**: `Esc` at the logo, Boot Manager.
  If the stick is not listed, rewrite it with balenaEtcher and try another
  USB port.
- **Jetson stuck in a firmware update loop**: section 5.2, step 2.
- **Jetson boots, but the first-boot wizard is a blank screen and no user
  account exists**: the firmware capsule update in section 5.2, step 2 was
  skipped, so JetPack 6 era firmware is running under a JetPack 7 rootfs.
  Boot stick B again and press `Y`. Do not go hunting for a bootloader
  rescue first: on the Orin Nano the USB-C serial port is `ttyGS0`, a
  gadget Linux itself creates, so it shows nothing until Linux is already
  up, cannot interrupt GRUB, and cannot send a SysRq (a CDC-ACM gadget has
  no serial BREAK). The real debug UART is on header pins on the back of
  the carrier board and needs a 3.3 V USB-to-TTL adapter. Headless
  `oem-config` falls back to *that* port, not to USB-C, so unplugging
  DisplayPort does not move the wizard onto the USB-C console.
- **`/dev/i2c-N` permission denied**: log out and in after the script (group
  membership), or `sudo usermod -aG i2c $USER`.

## 8. The robot's network

Measured and decided on 2026-09-22, after an evening of chasing a robot that
was on the network and yet unreachable.

**Addresses are static.** ROS 2 discovery (Fast DDS) announces a node's
addresses once, when the node starts. When the Orin's Wi-Fi re-associated
and the router handed it a different lease (.7 one time, .31 the next),
every running node kept talking to every other running node and became
invisible to anything started afterwards - `ros2 topic hz`, a recorder,
RViz. Static addresses make a reconnect harmless:

```bash
nmcli con modify "SpectrumSetup-E2DD" ipv4.method manual ipv4.addresses 192.168.1.7/24     ipv4.gateway 192.168.1.1 ipv4.dns 192.168.1.1 ipv4.ignore-auto-dns yes
nmcli con modify "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.1.78/24     ipv4.gateway 192.168.1.1 ipv4.dns 192.168.1.1 ipv4.ignore-auto-dns yes
```

Reserve the same addresses in the router so its pool can never collide
with them. `jetson.local` (mDNS) also works from the laptop and H2-Host.

**The Wi-Fi is locked to one access point.** The house SSID is broadcast by
the Spectrum box (`2c:67:be:...`, upstairs, far side) and by an extender
(`28:94:01:...`, upstairs, middle), each on 2.4 and 5 GHz. Connecting to
each in turn from the robot's spot downstairs and running `iperf3` to a
wired host:

| Access point | Signal | robot -> wire | wire -> robot |
|---|---|---|---|
| extender 2.4 GHz (`28:94:01:B6:41:A4`) - what it picks by itself | -49 dBm | ~26 Mbit/s | ~30 Mbit/s |
| extender 5 GHz | -62 dBm | ~0.5 | 2.5-19 |
| **Spectrum box 2.4 GHz (`2C:67:BE:53:E2:E1`)** | -58 dBm | ~25-36 Mbit/s | **~56-107 Mbit/s** |
| Spectrum box 5 GHz | too weak to hold | | |

The extender wins on signal and loses on throughput, because everything it
carries makes a second wireless hop. So:

```bash
nmcli con modify "SpectrumSetup-E2DD" 802-11-wireless.bssid 2C:67:BE:53:E2:E1 802-11-wireless.band bg
nmcli con modify "SpectrumSetup-E2DD" wifi.powersave 2      # Realtek + power save = drops
```

The cost of the lock: where the box's 2.4 GHz does not reach, the robot has
no home Wi-Fi rather than a poor one. `802-11-wireless.bssid ""` undoes it.
Note the Realtek driver only lists the access point it is on while
associated; scan after `nmcli dev disconnect` to see them all.

**Profiles and priorities.** Home network priority 20, the laptop's hotspot
(`DESKTOP-HIDD2LV 8567`, `192.168.137.x`) priority 10: home wins when both
are visible, the hotspot takes over automatically away from home. Windows'
mobile hotspot has been seen dropping the robot silently (association kept,
no traffic), so it is a field convenience, not a link to trust.

**Still open.** A second, longer-range, IP-native link for the field - the
old HC-12 serial radio is retired. Candidates: Wi-Fi HaLow (802.11ah,
900 MHz, ~1 km, a few Mbit/s, one USB adapter per end) or an LTE modem with
a data SIM. Whatever it is, it carries SSH and a small lifeline (heartbeat,
status, stop); the ROS traffic stays pinned to the Wi-Fi interface. Also:
the Windows laptop does not answer ping (its firewall), so measure links
to it with TCP, not `ping`.

## Sources

- Ubuntu 24.04 images and checksums: <https://releases.ubuntu.com/24.04/>;
  the pulled 24.04.5 desktop image: <https://www.omgubuntu.co.uk/2026/09/ubuntu-pulls-24-04-5-download>
- ROS 2 Jazzy installation: <https://docs.ros.org/en/jazzy/Installation/Ubuntu-Install-Debs.html>;
  distributions and support dates: <https://docs.ros.org/en/jazzy/Releases.html>;
  target platforms per distribution: [REP-2000](https://www.ros.org/reps/rep-2000.html)
  and <https://docs.ros.org/en/jazzy/Releases/lyrical/supported-platforms.html>
- JetPack downloads (Jetson ISO): <https://developer.nvidia.com/embedded/jetpack/downloads>
- Jetson Orin Nano Developer Kit user guide: [Quick Start](https://docs.nvidia.com/jetson/orin-nano-devkit/user-guide/latest/quick_start.html),
  [BSP setup](https://docs.nvidia.com/jetson/orin-nano-devkit/user-guide/latest/setup_bsp.html),
  [JetPack 6.x update path](https://docs.nvidia.com/jetson/orin-nano-devkit/user-guide/latest/update_firmware.html)
- NVIDIA forum guide: [Setting up the Orin Nano Super on JetPack 7.2](https://forums.developer.nvidia.com/t/setting-up-the-nvidia-jetson-orin-nano-super-dev-kit-on-jetpack-7-2-a-practical-guide-june-2026/372490)
- JetPack 7.2.1 release summary: <https://jetsonhacks.com/2026/08/12/jetpack-7-2-1-released/>
- Isaac ROS releases (4.6 = JetPack 7.2 + Jazzy): <https://nvidia-isaac-ros.github.io/releases/index.html>
- Orin Nano 40-pin header: <https://jetsonhacks.com/nvidia-jetson-orin-nano-gpio-header-pinout/>
- NVIDIA SDK Manager: <https://developer.nvidia.com/sdk-manager>
