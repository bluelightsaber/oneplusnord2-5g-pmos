# denniz bring-up notes

Chronological findings. Device: OnePlus Nord 2 5G **DN2103** (EU), device prop `OP515BL1`, codename *denniz*,
board `k6893v1_64_k419`, `androidboot.prjname=20831`. Not A/B, dynamic partitions (`super`), UFS 3.1.

## 1. Unlocking: only possible on OxygenOS 11
- OnePlus removed fastboot (and BROM entry) from the OOS 12/13 preloader/LK. On OOS 13 the way back is the
  **official rollback package** to OOS 11 (local install from Settings; if "local install" is greyed out, a pending
  OTA blocks it: airplane mode + clear data of "Software update"/`com.oplus.ota` and `com.oplus.sau`, reboot).
- On OOS 11 A.20: `adb reboot bootloader` → USB `0e8d:201c`, product `oplus6893`, `fastboot flashing unlock`
  works (confirm on screen; wipes data).
- **First boot after the unlock wipe**: the phone enumerated as Android Open Accessory with audio (`18d1:2d03`)
  and the host's `snd-usb-audio` hung the USB stack for 20 minutes. Blacklist `snd_usb_audio` on the build host,
  or keep the phone unplugged during wipes and first boots.
- `fastboot boot IMG` → "Booting FAILED (usb_read failed)": **not supported**. Test images go to `recovery`.

## 2. Backup
- Official TWRP 3.7.0_11-0-denniz flashed to `recovery`, started with `fastboot reboot recovery` (directly, so
  Android does not regenerate the stock recovery first). adb root in TWRP.
- All partitions except userdata, the preloader LUNs (`sda`, `sdb`) and the GPT: `scripts/dump-from-recovery.sh`.
- `adb exec-out` truncates or stalls on long streams (a 10 GB `super` stalled at 7.86 GB) → `scripts/dump-chunked.sh`
  reads 256 MiB chunks and compares per-chunk sha256 phone vs host.
- `adb shell` inside a `while read` loop eats the loop's stdin: use another fd or `</dev/null`.
- The live device tree LK passes to the kernel: `/sys/firmware/fdt` from TWRP (LK picks `dtbo_idx=2`).

## 3. BROM safety net
- Phone off, cable out, hold **Vol+ and Vol−**, plug in → `0e8d:0003`. Target config 0xe5: SBC on, DAA on,
  SLA off, memory read/write auth on. mtkclient uses **Kamakiri** with `mt6893_payload.bin` (hw code 0x950).
- Read-only test (`scripts/brom-test.sh`): GPT + `seccfg` + `lk` read via BROM, identical to the TWRP backup.
- Do **not** end the mtkclient session with `reset`: here it left the phone re-enumerating and the host's xhci stuck
  until the cable was pulled. Unplug, then Power + Vol+ for ~15 s.
- Staying on the OOS 11 preloader keeps BROM reachable (the "restore BROM" packages exist because OOS 12/13 block it).

## 4. Kernel: MT6891-Mainline tree
- `github.com/MT6891-Mainline/linux`, branch `7.3.3-mt6893-xiaomi-chopin` (Linux 7.3.3). Same SoC, same PMICs
  (MT6359 + MT6360 sub-PMIC on i2c5 at the same addresses), same LK generation.
- Their board DT is LK's flattened vendor tree restated for mainline (raw phandle numbers shared between
  `mt6893.dtsi` and the board file), **embedded in the kernel** (`arch/arm64/kernel/chopin-dtb.S`) and swapped in by
  `setup_arch()`, because LK must be given a tree it can apply `dtbo` to.
- Debugging without serial: `mtk-logstore-console` writes the kernel log into LK's log_store ring (0x7ffbf000,
  SRAM header 0x11df00 — same on denniz); LK relays it into the `expdb` partition on the next boot. `head.S` also
  drops K00..K03 breadcrumbs there.

## 5. denniz board tree (`scripts/mk-denniz-dts.py`)
Differences found by diffing the decompiled trees (`scripts/dtpaths.py`):
- RAM 12 GB (`reg = <0 0x40000000 3 0>`).
- **reserved-memory is different** (TEE 0x7a700000 + 0x5500000, framebuffer 0x78810000 + 0x1df0000, …). The tree
  was captured from a recovery-mode boot, which has **no modem/SCP/ADSP carve-outs** (LK does not load them in
  recovery mode). Good for the recovery slot only; the normal-boot tree must be captured before using `boot`.
- Command-mode panel (`atag,videolfb`: samsung ams643ye05 1080p dsi cmd): the LK logo simply stays.
- Board devices are OPlus ones (mp2650 charger, bq27541 gauge, charge pumps, focaltech touch …): the Xiaomi
  board devices of the chopin file are disabled (i2c0/2/4/5/6/7/8/9, spi0/1/5, dsi0, touch, SCP helper,
  sensor hub). USB is peripheral-only (no role switch, no VBUS boost).
- chopin hardcodes its framebuffer at 0x77a20000 in `head.S`, the log_store driver and `mtk_crtc.c`; on denniz
  that is ordinary RAM → moved to 0x78810000, DRM disabled for now.

## 6. Boot image
- Header v2, page 2048, base 0x40000000. The **dtb section of the stock boot.img is an Android DT table** (magic
  `d7b7ab1e`), not a bare FDT; TWRP carries the same one. `scripts/bootimg2.py` keeps it whole.
- LK log (from `expdb`): `mblock_reserve kernel_addr_mb 0x40080000 sz 0x7c00000`, `ramdisk_addr_mb 0x51100000
  sz 0x4000000`, `dtb_kernel_addr_mb 0x47c80000`. With `kernel_addr = 0x40200000`:
  `Warning! kernel_addr (0x40200000) is not taken from mb (0x40080000)` + `ASSERT at app/mt_boot/mt_boot.c:567`
  → Android reports `ro.boot.bootreason=lk_crash`. **Use 0x40080000**; the kernel only warns
  "Kernel image misaligned at boot" and runs.

## 7. First boots (2026-11-14/15)
1. `kernel_addr` 0x40200000 → LK assert (above).
2. Kernel runs: 8 CPUs at EL2, 12 GB, ramoops at 0x48090000 — then an **RCU stall in `mtk_eint_do_init`** right
   after `EINT 12 left unmasked (owned by another core)`, watchdog reboot (`bootreason=Watchdog`). `mt6893.dtsi`
   keeps EINT 12 unmasked for chopin's SCP sensor line; on denniz it storms → `/delete-property/
   mediatek,eint-keep-unmasked` on `&pio`.
3. Boots to the initramfs, but the legacy `g_serial` gadget (built in) grabs the UDC (`0525:a4a7`, "Gadget Serial
   v2.4 … Linux 7.3.3 with mtu3") and `USB_CONFIGFS` was a module → `USB_G_SERIAL` off, `USB_CONFIGFS=y`.
4. **Works**: gadget `18d1:d001` 15 s after `fastboot reboot recovery`, ACM root shell, MemTotal 11.3 GB, UFS
   (`ufshcd-mtk`, Samsung KLUEG8UHDC-B0E1, LUNs sda/sdb/sdc), mtu3 device mode.

## 8. postmarketOS from RAM, SSH over USB (2026-11-15)
Nothing is written to UFS yet. The userland is pmOS edge for the generic `qemu-aarch64` device (console UI,
systemd), built with `pmbootstrap install --no-image` and packed as a tarball (`scripts/pmos-rootfs.sh`, ~600 MB,
~1 GB unpacked). The kernel is ours with everything needed built in, so no modules are shipped.

`scripts/pmos-ram.sh`:
1. flash the test image to `recovery`, `fastboot reboot recovery` (the initramfs brings up ECM + ACM);
2. give the host side of the ECM link 172.16.42.2 and serve the tarball with `python3 -m http.server`;
3. over the ACM shell: mount a 6 GB tmpfs on `/newroot`, `wget -O - … | tar xz` (about 35 s);
4. write `/sbin/init` into `/tmp/switchroot`: PID 1 of the initramfs moves `/dev`, `/proc` and `/sys` into the new
   root and `exec switch_root`s. The gadget and the usb0 address survive the switch;
5. `ssh user@172.16.42.1`.

Result: systemd reaches its default target in 6 s of userspace, 8 CPUs, 11 GB RAM, the 238 GB UFS LUN is visible.
Failing units are kernel-config gaps: `nftables` (no `NF_TABLES`) and zram swap (no `ZRAM`); the clock starts in
the past (no RTC driver yet, no network time).

pmbootstrap notes: the config key for the init system is `service_manager` (`default`/`openrc`/`systemd`);
`--no-image` skips copying SSH keys (the script installs `authorized_keys` itself), and the default
`ssh_key_glob` (`~/.ssh/*.pub`) copies every public key of the build user, so point it at one dedicated key.
NetworkManager is told to leave `usb0` alone, because the initramfs already configured it.

## 9. Wi-Fi (2026-11-16)
The MT6891-Mainline tree carries MediaTek's downstream connectivity stack for the MT6893 (`conninfra` +
`wlan_drv_gen4m`, chip `soc3_0`, AXI bus, "CONNAC2" WFDMA). It is SoC-level, so the chopin DT nodes work on denniz
unchanged. The firmware comes from the phone's own backup (`vendor` inside `super`, read with `scripts/lpinfo.py`
and debugfs, nothing mounted; the NVRAM blob `WIFI` from `nvdata`), packed by `scripts/wifi-fw.sh`. None of it is in
this repository.

Lessons, in the order they showed up:
1. The firmware and the NVRAM blob must be in the **initramfs**: the driver probes within ~12 s of boot, and a late
   NVRAM blob makes power-on and pre-calibration race (retries, `RST_DRV_OWN_FAIL`, bus hang).
2. In a tarball unpacked over pmOS, use `usr/lib/firmware` (pmOS has `/lib -> usr/lib`; a `lib/` entry replaces the
   symlink and the system loses `/sbin/init`).
3. NetworkManager's MAC randomization breaks authentication (the firmware transmits with the NVRAM MAC): set
   `wifi.scan-rand-mac-address=no` and `wifi.cloned-mac-address=permanent`.
4. The driver's debug output is compiled out in user builds (`BUILD_QA_DBG=0`, also needed by conninfra). The patch
   adds `DENNIZ_WLAN_LOG` to keep the printing; raise levels per module with
   `echo 0xMODULE:0xLEVEL > /proc/net/wlan/dbgLevel`.
5. **The real bug.** Scan and association worked, DHCP even worked on an open network, but no unicast frame and no
   WPA handshake message 2 ever left. After ~8 data frames the TX-done, command-done and event interrupts stopped,
   followed ~45 s later by a scan timeout and a whole-chip reset. Dumping the host WFDMA registers with `devmem2`
   (`scripts/wfdma-devmem.sh`; chip address `0x7c02xxxx` = physical `0x1802xxxx`) showed host WFDMA1 **TX ring 2
   with BASE = 0 and CNT = 0x200 (reset values) but CPU index 2**. `soc3_0` declares a third data ring for
   "priority" frames (ARP, EAPOL, …): the first such frame made the DMA engine fetch descriptors from address 0 and
   hang. The register accepts a value written by hand, so the driver simply never programs it on this setup. The
   patch sets `tx_ring2_data_idx = 0`, so those frames use ring 0.
   (A 32-bit DMA mask with 12 GB of RAM looked suspicious first, but all rings and buffers live in
   `wifi-reserve-memory`, below 4 GB.)

Result: WPA2 connects on the first try, 0 % ping loss, about 700 Mbit/s TCP in each direction on 5 GHz.
`scripts/nat-usb.sh` (NAT on the host over the USB link) was the stop-gap for internet before that.

## Reading a failed boot
Flash TWRP back to `recovery`, boot it, dump `expdb` (`scripts/dump-chunked.sh OUT expdb:/dev/block/sdc8`) and run
`strings`: LK's log and the kernel log are there. pstore is overwritten by the Android boot in between.
