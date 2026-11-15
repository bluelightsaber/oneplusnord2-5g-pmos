# OnePlus Nord 2 5G as a server — checklist

Updated: 2026-11-15. Project directory on the host: `/srv/nord2-pmos/`.

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
- [ ] Kernel config for server use: nftables/NAT, Docker requirements, zram, i2c-dev, RTC
- [ ] Persistent rootfs on internal storage instead of RAM
- [ ] LK normal-boot DT captured (modem carve-outs) before anything goes to `boot`
- [ ] Installed to internal storage; clean reboots; reboot to fastboot from Linux
## Level 2 — safety nets
- [ ] experiment-fallback, usb-gadget-ensure, persistent journal (50M)
## Level 3 — power
- [ ] Charging; 45–65 % charge limit; battery health checked
## Level 4 — network
- [ ] USB host + Ethernet hub (auto role); Wi-Fi if possible
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
