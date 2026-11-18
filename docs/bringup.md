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

Afterwards: a 30-minute soak (900/900 pings, no chip reset), and NetworkManager connects on its own at boot.

## 10. Battery fuel gauge (2026-11-16)
The phone's own tree calls it `oplus,bq27541-battery` at 0x55 on i2c7 (`11d03000`), but flags it
`qcom,batt_bq28z610` and runs that bus at 100 kHz. Described as `ti,bq27541` at 400 kHz it never ACKed; as
`ti,bq28z610` at 100 kHz the mainline `bq27xxx_battery` driver reads it fine (2S pack, voltage, state of charge,
cycle count, health, temperature). The chopin children of i2c7 (NFC, camera LDO) are deleted in the generated DT;
0x68 on the same bus is the OnePlus charge pump and is left alone. The chargers themselves (MT6360, MPS MP2650,
charge pump, fast-charge MCU) have no Linux drivers; the charge limit (section 11) works at register level.

## 11. i2c, charger and charge limit (2026-11-16)
- Mainline `i2c-mt65xx` is DMA-only, but i2c10..13 have no APDMA channel: `scripts/patch-i2c-fifo.py` adds a
  FIFO/PIO mode (up to 8 bytes per message, DT flag `mediatek,fifo_only`). The vendor DT clock indices for those
  buses were also one too high for the mainline binding (each bus gated its neighbour's clock), fixed in the
  generated DT.
- The **MPS MP2650** charger (0x5c) is then readable (`scripts/mp2650-dump.sh`; register map from the OnePlus GPL
  driver). LK leaves its watchdog off, so the `CHG_EN` bit can be toggled safely. `scripts/charge-limit.sh` +
  `config/charge-limit.service` keep the battery between 45 and 65 % by writing only that bit; current, voltage
  and the other chargers (MT6360, charge pump) are left as LK set them.
- USB dual role: `dr_mode = "otg"` with a role switch; `scripts/usb-mode.sh host|device|try SECS` switches with a
  timed fallback to device mode (a systemd timer, so it survives the SSH session that started it). The port is
  USB 2.0 only, so NetworkManager prefers Wi-Fi (`config/50-denniz-route-metric.conf`).
- Bluetooth: MTK BTIF + combo driver with the phone's own firmware; works with bluez.

## 12. Wi-Fi: broadcast and ARP with PMF (2026-11-16)
After the TX fix, WPA2 worked but the phone stopped receiving broadcast/multicast after a while: other hosts could
not ARP it (the phone's own traffic was fine). Raising the RX debug level showed every group frame dropped as
"plain text during security connection" with WLAN index 0, while the group key was correctly in WTBL entry 5.
Dumping the hardware WTBL (`GET_WTBL` through `/proc/net/wlan/driver`) showed entry 0 holding the AP address with
no cipher: with PMF the driver installs the IGTK (BIP) at the entry equal to the BSS index ("WTBL 0-3 reserved
for BIP"), the firmware leaves that entry with the AP address, and the RX address search then matches group frames
to it. `scripts/patch-wifi-gtk-wtbl.py` puts the station's group key in that same entry, next to the IGTK.
Result, with PMF on: 40/40 test broadcasts received and a 60-minute idle ARP soak without a miss
(`scripts/arp-idle-test.sh`). Note: `GET_WTBL` while the station is (re)associating crashed the phone; use it
only on a stable connection.

## 13. GPU: Mali-G77 MC9 (2026-11-16)
The tree's panfrost works once the MFG power-domain clock provider (`COMMON_CLK_MT6893_PG`) is enabled:
`mali-g77 id 0x9080`, 9 shader cores. Alpine's Mesa 26.3.0 does not know the G77, so `scripts/mesa-g77-*.sh`
rebuild the same Mesa release on the phone (sources checked against Alpine's APKBUILD sums) with
`scripts/mesa-g77-patch.py`:
1. a Mali-G77 model entry (as in MT6891-Mainline's Mesa fork);
2. v9 (job manager) compute jobs split across the cores like the CSF path does. Stock code used one task for the
   whole grid, so OpenCL ran on a single core.

Results: GLES 3.1 (`scripts/gles-tri.c`), Rusticl OpenCL 3.0 with 9 compute units and fp16. `scripts/cl-bench.c`
reaches 159 GFLOPS fp32 ALU (19 before the split patch), 19.5 GB/s copy, and 12.7 GFLOPS for a simple tiled SGEMM,
with results checked against the CPU. PanVK has no v9 support.

## 14. Server stack (2026-11-17)
The kernel config covers Docker (namespaces, cgroup v2 incl. block I/O throttling, overlayfs, veth, bridge,
`nft_compat`), WireGuard and nftables. The rootfs (`scripts/pmos-rootfs.sh`) adds Docker, compose, buildx,
postmarketOS' nftables rules for Docker and Tailscale (`config/52_tailscale.nft`). In a RAM boot Docker 29.10 runs
with overlayfs, cgroup v2 and the systemd cgroup driver with no `docker info` warnings, containers reach the
network, and tailscaled is up waiting for a login. `scripts/soak.sh` logs the health of a long run.

## 15. Display: panel console (2026-11-17/18)
The panel is a Samsung AMS643YE05 (1080x2400 AMOLED, MIPI-DSI command mode, DSC 1.1, 4 lanes). Porting the
OnePlus panel driver to the tree's vendor `mediatek_v2` DRM (`kernel/panel-oneplus-denniz-ams643ye05.c`,
`DENNIZ_DISPLAY=1`) got as far as triggers without finished frames: the vendor driver pushes command-mode frames
from a GCE (command queue) loop, and this tree's CMDQ is a stub.

What works instead is to **keep what LK set up**. LK leaves the whole dual-pipe OVL → DSC → DSI path programmed
and scanning its framebuffer. With `DENNIZ_LKFB=1`:
- the board DT points a `simple-framebuffer` at LK's buffer (0x78810000, 1080x2400, pitch 4352, a8r8g8b8), so
  simpledrm + fbcon draw there;
- `kernel/denniz-lkfb.c` (built in) re-triggers the path from a delayed work item: clear the DSI interrupt status,
  enable the display mutex, toggle `DSI_START`, skipped while the DSI is busy. Rate `denniz_lkfb.hz` (default 2,
  0 = stop); the CPU cost is negligible. It refuses to run unless LK left DSI in command mode with the mutex
  configured, and clears LK's logo overlay layer once;
- fbcon is rotated to landscape (`rotate_all=1`) with the 16x32 Terminus font: 150x33 characters.

Two traps cost most of the time:
- The tree's `mtk-logstore-console` has an `fb_mirror` work item that copies a *second* candidate buffer
  (0x78e0c000) over 0x78810000 every 2 s, written for a board where LK sometimes scans the other buffer. Here it
  made the panel alternate between the live console and a stale frame. LKFB builds start it disabled
  (`/sys/kernel/debug/logstore/fb_mirror`).
- simpledrm ignores fbdev blanking, so "blank" only froze the last frame. `config/screen/screen-idle` paints the
  console black through `/dev/fb0` (black = pixels off on AMOLED), lets one frame go out, then sets `hz=0`.

`config/screen/`: `btop-console.service` (btop on tty1), `screen-idle` (blank after 1 h without input, SIGSTOP
btop; any key wakes), `kernel.printk = 3 4 1 7` so kernel messages do not paint over btop, and logind ignoring a
short power-key press. The long press is ignored too (§19): Linux poweroff hangs here, and a long hold is the
manual reset path.

## 16. USB-C: hub, Ethernet, automatic role (2026-11-18)
The port is USB 2.0 only (`mtu3` dual role + `xhci-mtk`). Forcing host mode
(`echo host > /sys/class/usb_role/11201000.usb-role-switch/role`) with a powered USB-C hub gives a working
RTL8153 Gigabit Ethernet (`r8152`, DHCP from NetworkManager; route metrics keep Wi-Fi first and Ethernet as
fallback, tested by switching Wi-Fi off), USB storage (~40 MB/s, the USB 2.0 limit), and the phone powered from
the hub.

**Automatic role.** The Type-C controller is the MT6360's TCPC (i2c bus at 0x11f00000, address 0x4e), which the
board tree had left disabled. With `DENNIZ_TYPEC=1` only the MT6360 TCPC is enabled (its charger stays off; denniz
charges with the MP2650) and the connector is a **sink only**, so the phone never sources VBUS.
`scripts/patch-typec.py` fixes two things in the tree:
- the tree's MT6360 platform driver unmasks the TCPC alerts after probe but leaves out `POWER_STATUS`, so TCPM
  never learned that VBUS was present and stopped in `SNK_DEBOUNCED`;
- a sink-only port does not toggle, so a source already connected at boot (or still there after a detach) never
  raised a CC-change event and was never attached. TCPM now attaches from the CC state it already has.

The tree's sink PDOs also offered 9 V and 12 V. The hub accepted 12 V and dropped VBUS during the transition, and
TCPM detached and retried in a loop (the voltage never rose, per the MP2650's ADC). The connector now offers
5 V / 3 A only, with the dual-role-data flag.

Result with a PD hub: attach, a 5 V contract, then **the hub requests a data-role swap** and the phone becomes the
USB host by itself, as on Android. Back on a PC cable the phone attaches as a device. `scripts/usb-role-auto.sh`
does what TCPM does not: `mtu3` does not pull D+ up again after host → device, so the configfs gadget is re-bound
to the UDC. If a partner is attached but no PC configures the gadget, it asks for a DR swap, and if the partner
cannot swap (no PD) it forces host mode. On kernels without the TCPC it switches roles from gadget and enumeration
state alone.

The first-boot initramfs keeps a respawning root shell on the ACM gadget (`/dev/ttyGS0`). That loop used to
survive `switch_root`; once the gadget went away (host mode) it spun and printed "sleep: not found" on the
console. `init` now kills it before switching root.

## 17. Robustness (2026-11-17)
- systemd feeds the hardware watchdog (`RuntimeWatchdogSec=30s`); two out-of-memory hangs during large builds
  rebooted the phone on their own.
- `scripts/wifi-ensure.sh`: the gen4m Wi-Fi driver can hang with a full TX ring (WFDMA1 TX0). The service pings the
  gateway every 10 s and, after three misses, logs two dumps of the WFDMA0/1 ring registers plus link and
  neighbour state to the journal, then power-cycles the radio (`nmcli radio wifi off`, a WMT power write through
  `/dev/wmtWifi`, `nmcli radio wifi on`). Outage ≈ 40 s. See §21.
- CPU inference with llama.cpp (Qwen2.5-0.5B Q4_K_M, 8 threads): 45 tokens/s prompt, 22 tokens/s generation. On
  the GPU, Rusticl's compiler (libclang 23) crashes on some ggml OpenCL kernels; not pursued.

## 18. Persistent install (2026-11-18)
Plan: keep Android's partition layout (no repartitioning) and reuse the two big partitions.
1. **Backup.** `scripts/full-backup.sh` runs from the RAM system: `sfdisk -d/-l` of every LUN, the first and last
   MiB of each LUN (primary and backup GPT), whole `sda`/`sdb` (preloader), every `sdc` partition, sha256 on the
   phone and on the host for each image. The 226 GiB `userdata` was streamed later over Wi-Fi with `zstd -1 -T6` on
   the phone (raw sha256 through a fifo): 3.1 GB, verified.
2. **Root on `super`.** `scripts/persist-rootfs.sh` formats `super` (the dynamic-partition container with
   system/vendor/product; ~10 GiB) as btrfs `pmos-root`, subvolume `@`, and rsyncs the running, tested RAM system
   into it (no CoW for `/var/log`, persistent journal capped at 50 MB). This removes Android.
3. **Persistent initramfs.** `PMOS_ROOT=super scripts/mk-initramfs.sh` writes `/pmos_root` into the initramfs:
   `init` finds the partition by `PARTNAME`, mounts `subvol=@` and `switch_root`s. If that fails it stays in the
   initramfs with the USB shell. The image went to `recovery` first (`fastboot reboot recovery` → first persistent
   boot), then, once that worked, to `boot`. `recovery` keeps the same known-good image as the rescue path.
4. **Data disk.** `scripts/persist-data.sh` formats `userdata` as btrfs `pmos-data` with subvolumes `@data`,
   `@docker`, `@containerd` mounted at `/data`, `/opt/docker` (Docker `data-root`) and `/var/lib/containerd`
   (Docker 29's containerd image store), `compress=zstd:1`, `nofail` and a 20 s device timeout so a broken data disk
   never blocks the boot; Docker and containerd get `RequiresMountsFor`.

A normal boot takes ~2 minutes: LK sits ~90 s with the panel off before the logo (not investigated yet; a
recovery-mode boot of the same image takes ~6 s). The phone boots and joins Wi-Fi with no cable attached.

Updates: the rootfs is a regular postmarketOS install (`apk upgrade`). Our kernel and modules are not managed by
apk (the generic kernel package only writes to `/boot`, which LK never reads), so updates do not touch them.

## 19. Reboot target from Linux (2026-11-18)
LK reads the reboot reason from the **TOPRGU `nonrst2` register (0x10007024, low nibble)**. The map comes from
LK's own embedded device tree (`/watchdog@10007000/reboot-mode`, `syscon-reboot-mode`, offset 0x24, mask 0xf):
charger 1, **recovery 2**, **bootloader 3**, kpoc 5, meta 7, kernel 9, ftm 0xe. Results with `devmem2` + reboot:
- **2 → LK boots `recovery`** in ~6 s.
- **3 → LK hangs** with the panel off for ~90 s, then the hardware watchdog resets it into recovery. USB never
  enumerates, so there is no software path to fastboot; fastboot still needs Vol− + Power from power-off.
- 0 or 9 → normal boot (`boot`).

`config/reboot/denniz-reboot-mode` is a systemd-shutdown hook: on reboot it takes `systemctl reboot
--reboot-argument=recovery|bootloader|normal` (or `/etc/denniz-reboot-default`) and sets the nibble. The kernel has
`CONFIG_SYSCON_REBOOT_MODE`, so the same node could go into the board DT later.

`config/reboot/powerkey-rescue`: hold power for 4 s → reboot into recovery (reads the `mt6359` pmic-keys event
device; logind ignores the long press). Holding ~15 s still triggers the PMIC hardware reset. Linux poweroff does
not cut power on this board (it hangs), so the banner says to reboot instead.

## 20. SSH welcome banner (2026-11-18)
`config/motd/99-denniz-welcome.sh` (installed as `/etc/profile.d/99-denniz-welcome.sh`, interactive SSH only, once
per login, `~/.hushlogin` skips it): kernel, uptime, battery and charge state, hottest thermal zone, load, IP
addresses, disk usage of `/` and `/data`, Docker counts, then a short "how this server works" (storage, Docker
folders, `apk` updates, network tools, USB-C roles, power key, reboot/rescue, battery limit, logs).
`pmos-rootfs.sh` installs it (`WELCOME_LANG=es` for the Spanish version).

## 21. Wi-Fi TX hang (open, 2026-11-18)
Symptom: the gateway becomes unreachable and the WFDMA1 TX0 ring stops moving; wifi-ensure recovers it. Hangs seen
after ~1 h of sustained TX, but also once 5 minutes after boot with almost no traffic. The kernel message
`halCheckHifState: Tx timeout` means an MSDU token has been in use longer than the report timeout (checked every
perf-monitor tick); after a hang one token stays leaked and the message repeats every second while traffic works,
so it is not a hang by itself. 802.11 power save is already off. All hangs so far were on 5 GHz at high rates; after
a radio cycle the link came back on 2.4 GHz and survived long stress runs. Next: confirm the band dependency and
read the ring dumps from the next hang.

## Reading a failed boot
Flash TWRP back to `recovery`, boot it, dump `expdb` (`scripts/dump-chunked.sh OUT expdb:/dev/block/sdc8`) and run
`strings`: LK's log and the kernel log are there. pstore is overwritten by the Android boot in between.
