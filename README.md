# OnePlus Nord 2 5G (denniz) → postmarketOS headless server

Turning an old **OnePlus Nord 2 5G** (DN2103, codename *denniz*, MediaTek **MT6893 / Dimensity 1200**, 12 GB RAM,
256 GB UFS) into a small Linux server running postmarketOS with a **mainline kernel**, to keep working hardware
out of the e-waste bin.

This repository collects the scripts, kernel patch, device tree and notes of the bring-up, as it happens.
It is a personal hobby project, not an official postmarketOS port.

> **Warning.** Everything here writes to a phone's flash at some point. Read the scripts before running them,
> keep a full partition backup, and never write the IMEI/calibration partitions (`nvram`, `nvdata`, `nvcfg`,
> `protect1/2`, `persist`, `proinfo`, `md*`). No vendor firmware or partition images are included.

## Status (2026-11-16)

| Step | State |
|---|---|
| Bootloader unlock (via official OOS 11 rollback) | done |
| Full partition backup (TWRP in the recovery slot) | done |
| BROM access with mtkclient (read-only test) | done |
| Mainline kernel 7.3.3 boots from the `recovery` slot | **done** |
| USB device mode (configfs gadget: ECM + ACM root shell) | **done** |
| UFS storage (all LUNs visible) | **done** |
| postmarketOS rootfs (systemd) booted from RAM + SSH over USB | **done** |
| Kernel config for server use (nftables, Docker, policy routing, WireGuard) | **done** (zram backends in test) |
| **Wi-Fi** (MT6893 CONNAC2 `soc3_0`, WPA2, ~700 Mbit/s TCP) | **done** (RAM boot) |
| RTC (MT6359 keeps Android's encoding) | open |
| Production install in `boot`, charging limit, USB host/Ethernet, Docker … | planned |

The display is not driven yet (command-mode Samsung AMOLED); the LK boot logo stays on screen.

See [`docs/bringup.md`](docs/bringup.md) for the full log of findings and [`CHECKLIST.md`](CHECKLIST.md) for the
roadmap.

## How it boots

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
- Community research on denniz (XDA, the unofficial LineageOS builds by ManshuTyagi) for the rollback/BROM path.
- Methodology follows the author's sister project for the OnePlus 9 Pro:
  <https://github.com/bluelightsaber/oneplus9pro-postmarketos>.

## License
- Kernel patch and device tree (`patches/kernel/`, `dts/`): **GPL-2.0-only**, like the Linux kernel
  (`LICENSES/GPL-2.0`).
- Everything else (scripts, initramfs, docs): **MIT** (`LICENSE`).
