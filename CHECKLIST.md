# OnePlus Nord 2 5G as a server — checklist

Updated: 2026-11-16. Project directory on the host: `/srv/nord2-pmos/`.

## Level 0 — diagnosis, unlock, backup
- [x] Phase 0 diagnosis (DN2103, OP515BL1/denniz, MT6893, not A/B, `fastboot boot` NOT supported → test slot = `recovery`)
- [x] OOS 13 → official rollback to OOS 11 A.20 (fastboot only exists there)
- [x] Bootloader unlocked (2026-11-14)
- [x] Full partition backup (59 images via TWRP in recovery, sha256 verified; IMEI/calibration included, never published)
- [x] BROM safety net verified (mtkclient Kamakiri, read-only test; keep the OOS 11 preloader)
## Level 1 — boot
- [x] Kernel route decided: mainline (MT6891-Mainline 7.3.3 tree + own denniz board tree)
- [x] Kernel builds; denniz board DT, v2 boot image packer, USB initramfs, slot-test cycle ready
- [x] First boot from the `recovery` slot: USB gadget + shell (172.16.42.1 / ttyACM)
- [x] UFS visible, partitions listed
- [x] pmOS rootfs (systemd) booted from RAM (switch_root) + SSH over USB
- [x] Kernel config for server use: nftables/NAT, Docker requirements, zram (lz4/zstd), i2c-dev (built in)
- [x] RTC (MT6359 via rtc-mt6397): correct time at boot, NTP synced; RTC_SYSTOHC stays off (Android uses its own base)
- [ ] Persistent rootfs on internal storage instead of RAM
- [x] LK normal-boot carve-outs captured from LK's log in expdb (still to be applied to the DT before `boot`)
- [ ] Installed to internal storage; clean reboots; reboot to fastboot from Linux
## Level 2 — safety nets
- [ ] experiment-fallback, usb-gadget-ensure, persistent journal (50M)
## Level 3 — power
- [x] Battery gauge (TI bq28z610 on i2c7, 100 kHz): capacity, voltage, cycles, health in /sys/class/power_supply
- [ ] Charging control: MP2650 (0x5c, i2c11) readable via FIFO-mode i2c (`mp2650-dump.sh`, `docs/mp2650.md`); 45–65 % limit via CHG_EN
- [x] Overnight log on USB power (2026-11-16, 5 h): 0 lost pings, Wi-Fi stable, battery held at 100 % (not informative for drain)
## Level 4 — network
- [x] Wi-Fi (MT6893 CONNAC2 soc3_0, vendor firmware from the phone's own partitions): WPA2, ~700 Mbit/s
  (fix: soc3_0 TX ring 2 is never programmed → priority ring disabled)
- [ ] USB host: dual-role mtu3 with manual role switch (`usb-mode.sh host|device|try SECS`)
- [ ] **Hub test** (as on the 9 Pro): powered USB-C hub with Ethernet (RTL8153) + pendrive. Procedure: hub powered,
      Ethernet to the router; `usb-mode.sh try 600` over Wi-Fi; move the cable from the host to the hub; check
      `lsusb`, `eth0` gets DHCP, phone keeps charging from the hub; mount the pendrive (vfat/exfat/ntfs3) and read files;
      `touch /run/usb-host-keep` to stay in host mode. Then: automatic role choice.
- [ ] NM priority **Wi-Fi first, Ethernet only as fallback** (reverse of the 9 Pro; USB 2.0 Ethernet is slower than
      Wi-Fi): route metrics 100 vs 700 in `config/50-denniz-route-metric.conf`
## Level 5 — services
- [ ] userdata as btrfs data disk (/data, /opt/docker, /var/lib/containerd)
- [~] NTP, Docker, Tailscale, nftables, user `phone` — NTP/timezone, Docker 29.10 (overlayfs, cgroup v2), nftables
  (pmOS + 51_docker + 52_tailscale) and tailscaled verified in RAM (usb21/usb23); Tailscale logged in, node state
  restored on every RAM boot (kept privately on the host); pending: user `phone`,
  Docker data-root on the data disk
## Level 6 — maintenance
- [ ] Kernel update cycle following pmOS
## Level 7 — extras
- [ ] Bluetooth (BTIF, vendor firmware soc3_0_ram_bt)
- [~] Panel driver (Samsung AMS643YE05, DSI command mode) → framebuffer console on screen — driver ported
  (opt-in `DENNIZ_DISPLAY=1`), binds with fbcon; CPU frame trigger runs but DSI does not complete frames yet
- [ ] btop always running on the panel console (landscape), as on the 9 Pro
- [ ] Screen idle: blank after 1 h; any button press wakes it for 1 h (logind HandlePowerKey=ignore)
- [ ] GPU (Mali-G77 MC9, Valhall): explore panfrost/panthor + Mesa (MT6891-Mainline mesa fork) and compute APIs
      (OpenCL via Rusticl, Vulkan via PanVK) as a hardware accelerator for ML workloads
- [-] Touch: dropped (not needed for a server)
## End
- [ ] Multi-day soak test as a server
- [ ] Cleanup on the host (udev/TLP entries)
