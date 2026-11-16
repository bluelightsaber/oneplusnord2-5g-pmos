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
- [ ] RTC (MT6359 reads 2069: Android keeps it with another base; never let Linux write it)
- [ ] Persistent rootfs on internal storage instead of RAM
- [x] LK normal-boot carve-outs captured from LK's log in expdb (still to be applied to the DT before `boot`)
- [ ] Installed to internal storage; clean reboots; reboot to fastboot from Linux
## Level 2 — safety nets
- [ ] experiment-fallback, usb-gadget-ensure, persistent journal (50M)
## Level 3 — power
- [x] Battery gauge (TI bq28z610 on i2c7, 100 kHz): capacity, voltage, cycles, health in /sys/class/power_supply
- [ ] Charging control (MP2650 charger has no mainline driver); 45–65 % charge limit
## Level 4 — network
- [x] Wi-Fi (MT6893 CONNAC2 soc3_0, vendor firmware from the phone's own partitions): WPA2, ~700 Mbit/s
  (fix: soc3_0 TX ring 2 is never programmed → priority ring disabled)
- [ ] USB host + Ethernet hub (auto role)
## Level 5 — services
- [ ] userdata as btrfs data disk (/data, /opt/docker, /var/lib/containerd)
- [ ] NTP, Docker, Tailscale, nftables, user `phone`
## Level 6 — maintenance
- [ ] Kernel update cycle following pmOS
## Level 7 — extras
- [ ] Console on screen, screen idle; panel (command mode); GPU; Wi-Fi/BT; touch
## End
- [ ] Multi-day soak test as a server
- [ ] Cleanup on the host (udev/TLP entries)
