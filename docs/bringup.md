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

## Reading a failed boot
Flash TWRP back to `recovery`, boot it, dump `expdb` (`scripts/dump-chunked.sh OUT expdb:/dev/block/sdc8`) and run
`strings`: LK's log and the kernel log are there. pstore is overwritten by the Android boot in between.
