# OnePlus Nord 2 5G (denniz) → postmarketOS headless server

Turning an old **OnePlus Nord 2 5G** (DN2103, codename *denniz*, MediaTek **MT6893 / Dimensity 1200**, 12 GB RAM,
256 GB UFS) into a small Linux server running postmarketOS with a **mainline kernel**, to keep working hardware
out of the e-waste bin.

This repository collects the scripts, kernel patch, device tree and notes of the bring-up, as it happens.
It is a personal hobby project, not an official postmarketOS port.

> **Warning.** Everything here writes to a phone's flash at some point. Read the scripts before running them,
> keep a full partition backup, and never write the IMEI/calibration partitions (`nvram`, `nvdata`, `nvcfg`,
> `protect1/2`, `persist`, `proinfo`, `md*`). No vendor firmware or partition images are included.

## Status (2026-11-18)

| Step | State |
|---|---|
| Bootloader unlock (via official OOS 11 rollback) | done |
| Full partition backup (TWRP in the recovery slot) | done |
| BROM access with mtkclient (read-only test) | done |
| Mainline kernel 7.3.3 boots from the `recovery` slot | **done** |
| USB device mode (configfs gadget: ECM + ACM root shell) | **done** |
| UFS storage (all LUNs visible) | **done** |
| postmarketOS rootfs (systemd) booted from RAM + SSH over USB | **done** |
| Kernel config for server use (nftables, Docker, policy routing, WireGuard) | **done** |
| **Wi-Fi** (MT6893 CONNAC2 `soc3_0`, WPA2 + PMF, ~700 Mbit/s TCP, broadcast/ARP fixed) | **done**; rare TX hang, auto-recovered in ~40 s (under investigation) |
| Bluetooth (MTK BTIF, bluez) | **done** |
| Battery fuel gauge (TI bq28z610) | **done** |
| Charge limit 45–65 % (MPS MP2650 `CHG_EN` only, systemd service) | **done** |
| USB-C: MT6360 TCPC + TCPM, USB-PD sink (5 V only), automatic host/device role (PD data-role swap) | **done** |
| USB hub: RTL8153 Gigabit Ethernet (Wi-Fi first, Ethernet fallback), USB storage, phone powered by the hub | **done** |
| GPU: Mali-G77 MC9 with panfrost + patched Mesa (GLES 3.1, Rusticl OpenCL 3.0) | **done** |
| Docker 29 + Tailscale + nftables (Docker data on the data disk) | **done** |
| Panel console: btop in landscape on the LK framebuffer (simpledrm + frame pusher), 1 h blank, key wake | **done** |
| RTC (MT6359) | done (NTP) |
| **Persistent install on UFS**: btrfs root on `super`, our kernel in `boot`, rescue image in `recovery` | **done** |
| Data disk: `userdata` as btrfs (`/data`, `/opt/docker`, `/var/lib/containerd`) | **done** |
| Software reboot into recovery (LK reboot-mode register), hold power 4 s = reboot to recovery | **done** |
| SSH welcome banner (live status + how the server works) | **done** |
| Software reboot into fastboot | not possible (LK hangs; watchdog → recovery) |
| Power off from Linux | hangs (does not cut power); hold power ~15 s |

The panel shows a `btop` console: LK leaves the display pipeline running, the kernel draws into LK's framebuffer
with simpledrm, and a small built-in driver (`kernel/denniz-lkfb.c`) pushes a frame to the command-mode panel twice
a second. Production kernels are built with `DENNIZ_LKFB=1 DENNIZ_TYPEC=1` (see the notes).

See [`docs/bringup.md`](docs/bringup.md) for the full log of findings and [`CHECKLIST.md`](CHECKLIST.md) for the
roadmap.

## How it boots

The installed system (since 2026-11-18):

```
BROM → preloader → LK → boot.img v2 from `boot`     → initramfs mounts btrfs `super` (subvol @) → systemd
                      → same image in `recovery`    → rescue path (power held 4 s, or `--reboot-argument=recovery`)
userdata = btrfs data disk: /data, /opt/docker, /var/lib/containerd
```

During the bring-up everything was tested from the `recovery` slot first:

```
BROM → preloader → LK (MediaTek little kernel) → boot.img v2 from the `recovery` partition
                                                  ├─ Image.gz  (our kernel, board DT embedded inside)
                                                  ├─ initramfs (busybox, USB gadget, root shell)
                                                  ├─ dtb section = the STOCK Android DT table (LK applies dtbo to it)
                                                  └─ recovery_dtbo (from the official TWRP image)
```

Key facts (details in the notes):
- `fastboot boot` is **not** supported by this LK, so test images go to the `recovery` partition (128 MiB) and
  are started with `fastboot reboot recovery` (one-shot, MediaTek RTC flag). `boot` stays untouched.
- LK insists on its own device tree (it applies `dtbo` and gives up otherwise). The kernel tree we use embeds the
  board DT in the kernel and swaps it in during `setup_arch()`.
- LK only accepts `kernel_addr = 0x40080000` (its `kernel_addr_mb` reservation); anything else is an LK panic.
- Without serial or display, failed boots are read back from the **`expdb`** partition: LK relays its own log
  and the kernel log (written into LK's `log_store` ring by `mtk-logstore-console`) there on the next boot.

## Layout

| Path | What |
|---|---|
| `patches/kernel/` | Patch on top of the MT6891-Mainline tree: denniz board DT, framebuffer addresses, `denniz_defconfig` |
| `dts/` | The generated `mt6893-oneplus-denniz.dts` (also inside the patch) |
| `scripts/mk-denniz-dts.py` | Generates the denniz board DT from the chopin board file + the phone's live LK tree |
| `scripts/patch-denniz.sh`, `build-kernel.sh` | Apply the changes on a local branch, build out of tree |
| `scripts/bootimg2.py`, `mk-test-img.sh` | Minimal boot image v2 packer, test image for the recovery slot |
| `initramfs-usb/`, `scripts/mk-initramfs.sh` | First-boot initramfs (USB gadget 18d1:d001, root shell on ACM, safety reboot) |
| `scripts/slot-test.sh`, `acm-run.sh` | Flash-and-boot test cycle and the host side of the USB shell |
| `scripts/pmos-rootfs.sh`, `pmos-ram.sh` | Build a pmOS rootfs tarball with pmbootstrap; boot it from RAM over USB and SSH in |
| `scripts/wifi-fw.sh`, `lpinfo.py` | Wi-Fi firmware + NVRAM from the phone's own `super`/`nvdata` backup (never published) |
| `scripts/wifi-ping-test.sh`, `wfdma-devmem.sh`, `eapol-test.sh` | Wi-Fi tests: connect + ping, host WFDMA ring dump, WPA capture |
| `scripts/nat-usb.sh`, `cycle.sh`, `tput.py` | Internet over USB via NAT on the host, reboot-and-retest cycle, TCP throughput |
| `scripts/brom-test.sh` | Read-only BROM check with mtkclient |
| `scripts/patch-wifi-gtk-wtbl.py`, `arp-idle-test.sh` | Wi-Fi group-key WTBL fix (broadcast/ARP with PMF) and its soak test |
| `scripts/patch-i2c-fifo.py` | FIFO mode for the i2c controllers without an APDMA channel |
| `scripts/charge-limit.sh`, `mp2650-dump.sh`, `config/charge-limit.service` | 45–65 % charge limit via the MP2650 `CHG_EN` bit, register dump |
| `scripts/usb-mode.sh` | USB host/device role switch with automatic fallback |
| `scripts/mesa-g77-*.sh`, `mesa-g77-patch.py`, `cl-bench.c`, `gles-tri.c` | Mesa with Mali-G77 support built on the phone, OpenCL/GLES tests |
| `kernel/denniz-lkfb.c`, `scripts/patch-lkfb.py`, `lkfb-tool.c` | Frame pusher for the LK framebuffer (panel console), /dev/mem debug tool |
| `config/screen/` | btop console service, `screen-idle` (1 h blank, any key wakes), quiet console, power-key policy |
| `scripts/patch-typec.py`, `usb-role-auto.sh`, `config/usb-role-auto.service` | MT6360 Type-C fixes; role helper (gadget re-bind, DR swap, fallback without TCPC) |
| `scripts/wifi-ensure.sh`, `config/wifi-ensure.service` | Wi-Fi watchdog: power-cycles the radio after a TX hang |
| `kernel/panel-*.c`, `scripts/patch-display*.py` | Experimental: AMS643YE05 panel driver for the vendor `mediatek_v2` DRM, CPU frame trigger (not used) |
| `config/` | NetworkManager route metrics (Wi-Fi first, Ethernet fallback), Tailscale firewall rule, Bluetooth name |
| `scripts/full-backup.sh` | Read-only full UFS backup from pmOS (tables, both GPT copies, every partition, phone/host sha256) |
| `scripts/persist-rootfs.sh`, `persist-data.sh` | Persistent install: copy the running RAM system to `super` (btrfs @); `userdata` as the data disk |
| `config/reboot/` | `denniz-reboot-mode` (systemd-shutdown hook setting LK's reboot mode), `powerkey-rescue` (hold power 4 s) |
| `config/motd/` | SSH welcome banner (English; `.es.sh` = Spanish) |
| `scripts/soak.sh` | Long-running health log (ping, load, battery, temperatures, services) |
| `scripts/dump-*.sh`, `twrp-to-recovery.sh` | Partition backup from TWRP (chunked, sha256-verified) |
| `scripts/dtpaths.py` | Node/compatible/status listing to diff two decompiled device trees |

Paths in the scripts assume a project directory `/srv/nord2-pmos` on a Linux build host with the phone attached
by USB; set `SERIAL` to your phone's adb/fastboot serial.

## Credits and references

This work stands on other people's work:
- **MT6891-Mainline** — <https://github.com/MT6891-Mainline/linux>, branch `7.3.3-mt6893-xiaomi-chopin`: the
  MT6893 mainline kernel (Redmi Note 10 Pro *chopin*), including the embedded board DT approach and the
  `mtk-logstore` debug console. Our patch is a board port on top of it.
- **mtkclient** by Bjoern Kerler — <https://github.com/bkerler/mtkclient>: BROM access (Kamakiri payload).
- **postmarketOS** and **pmbootstrap** — <https://postmarketos.org>.
- **TWRP** — official `twrp-3.7.0_11-0-denniz` (<https://twrp.me>), used for the partition backup.
- **OnePlus** — the official OxygenOS 11 rollback package (fastboot only exists on OOS 11 for this phone).
- **BusyBox** (static aarch64) in the first-boot initramfs.
- **OnePlus / OPPO kernel source** (GPL, `oneplus/MT6893_R_11.0`): the AMS643YE05 panel init sequence and DSC
  parameters, the MP2650 charger register map, and the gen4m Wi-Fi driver this work patches.
- **Mesa** / **panfrost** — <https://mesa3d.org>: our patch only adds the Mali-G77 model entry and splits v9 compute
  jobs across the shader cores; the G77 entry follows MT6891-Mainline's Mesa fork.
- **Docker**, **Tailscale**, **btop**, **Alpine Linux** packages used as-is; the Linux kernel's TCPM/TCPCI
  Type-C stack and the Terminus console font.
- Community research on denniz (XDA, the unofficial LineageOS builds by ManshuTyagi) for the rollback/BROM path.
- Methodology follows the author's sister project for the OnePlus 9 Pro:
  <https://github.com/bluelightsaber/oneplus9pro-postmarketos>.

## License
- Kernel patch, device tree and kernel driver (`patches/kernel/`, `dts/`, `kernel/`): **GPL-2.0-only**, like the Linux kernel
  (`LICENSES/GPL-2.0`).
- Everything else (scripts, initramfs, docs): **MIT** (`LICENSE`).
