#!/usr/bin/env python3
"""Generate mt6893-oneplus-denniz.dts (OnePlus Nord 2 5G) from the chopin board file.

The MT6891-Mainline chopin board file is the bootloader's vendor tree, restated for mainline. denniz runs the
same SoC, PMICs (MT6359 + MT6360 on i2c5) and the same LK, so this first, minimal board file keeps the chopin
SoC/PMIC side and replaces only what is board specific or dangerous:
  - /memory and /reserved-memory come from denniz's own live tree (captured from TWRP = recovery boot mode,
    so there are NO modem/SCP/ADSP carve-outs: valid for images booted from the recovery slot ONLY);
  - Xiaomi board devices (i2c0/2/4/5/6/7/8/9, spi0/1/5 children, panel, touch, charge pumps, SCP helper,
    sensor hub) are disabled;
  - USB is peripheral-only (no role switch, no VBUS boost).
Usage: mk-denniz-dts.py CHOPIN_DTS DENNIZ_LIVE_DTS OUT_DTS
"""
import os, re, sys
DISPLAY = os.environ.get('DENNIZ_DISPLAY') == '1'   # opt-in display bring-up
TYPEC = os.environ.get('DENNIZ_TYPEC') == '1'     # opt-in MT6360 TCPC (automatic USB host/device role)

def block(text, header_re):
    """Return (start, end) of the node whose header line matches header_re (end is after its '};\\n')."""
    m = re.search(header_re, text, re.M)
    if not m:
        sys.exit(f'not found: {header_re}')
    i, depth = text.index('{', m.start()), 0
    for j in range(i, len(text)):
        if text[j] == '{': depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0:
                e = text.index('\n', j) + 1
                return m.start(), e
    sys.exit('unbalanced braces')

chopin, live, out = sys.argv[1:4]
src = open(chopin).read()
dz = open(live).read()

# header
src = src.replace(' * Xiaomi Redmi Note 10 Pro (chopin)', ' * OnePlus Nord 2 5G (denniz) - generated from the chopin board file by scripts/mk-denniz-dts.py', 1)
src = re.sub(r'(\n/ \{\n)\tmodel = "[^"]*";\n\tcompatible = "mediatek,MT6893";',
             r'\1\tmodel = "OnePlus Nord 2 5G (denniz)";\n\tcompatible = "oneplus,denniz", "mediatek,MT6893";', src, count=1)
assert 'oneplus,denniz' in src

# debug-kinfo points at a chopin-only carve-out (aee_debug_kinfo): drop it
s, e = block(src, r'^\tdebug-kinfo \{'); src = src[:s] + src[e:]

# /memory from denniz
s, e = block(src, r'^\tmemory \{'); ds, de = block(dz, r'^\tmemory \{')
src = src[:s] + dz[ds:de] + src[e:]

# /reserved-memory from denniz, keeping the phandles the SoC dtsi uses
s, e = block(src, r'^\treserved_memory: reserved-memory \{'); ds, de = block(dz, r'^\t(reserved_memory: )?reserved-memory \{')
rm = dz[ds:de]
rm = re.sub(r'^\t(reserved_memory: )?reserved-memory \{', '\treserved_memory: reserved-memory {', rm, count=1, flags=re.M)
rm, n = re.subn(r'(wifi_mem: wifi-reserve-memory \{.*?phandle = )<0xb3>', r'\1<0xb2>', rm, count=1, flags=re.S); assert n == 1
rm, n = re.subn(r'(\t\tconsys-reserve-memory \{\n)', r'\1\t\t\tphandle = <0xed>;\n', rm, count=1); assert n == 1
rm, n = re.subn(r'(\t\tmblock-\d+-framebuffer \{\n)', r'\1\t\t\tno-map;\n', rm, count=1); assert n == 1
extra = set(re.findall(r'phandle = <(0x[0-9a-f]+)>', rm)) - {'0xfb', '0xb2', '0xed'}
assert not extra, f'unexpected phandles in denniz reserved-memory: {extra}'
src = src[:s] + rm + src[e:]

# chopin simplefb (LK video-mode panel at 0x78e0c000). denniz has a command-mode panel (samsung ams643ye05): off,
# unless DENNIZ_LKFB=1, which points it at denniz's LK framebuffer (0x78810000, same 4352 pitch and a8r8g8b8 as
# the OVL layer LK programs; 4352 * 2400 = 0x9f6000) for simpledrm; kernel/denniz-lkfb.c pushes the frames.
LKFB = os.environ.get('DENNIZ_LKFB') == '1' and not DISPLAY
if LKFB:
    src, n = re.subn(r'framebuffer@78e0c000 \{(.*?)reg = <0x0 0x78e0c000 0x0 0x9f6000>;',
                     r'framebuffer@78810000 {\1reg = <0x0 0x78810000 0x0 0x9f6000>;', src, count=1, flags=re.S)
    assert n == 1
else:
    src, n = re.subn(r'(framebuffer@78e0c000 \{.*?status = )"okay"', r'\1"disabled"', src, count=1, flags=re.S); assert n == 1

src += '''
/* ===================== denniz: first-boot overrides ===================== */
/* Board devices of the Xiaomi handset (or unknown wiring on denniz): off. */
'''
for lab in ['i2c0', 'i2c2', 'i2c4'] + ([] if TYPEC else ['i2c5']) + ['i2c6', 'i2c7', 'i2c8', 'i2c9', 'spi0', 'spi1', 'spi5']\
           + ([] if DISPLAY else ['dsi0']) + ['xiaomi_touch', 'cp_qc30', 'usbpd_pm', 'sensor_hub', 'scp_start']:
    assert re.search(rf'\b{lab}:', src + open(chopin.replace('mt6893-xiaomi-chopin.dts', 'mt6893.dtsi')).read()), lab
    src += f'&{lab} {{\n\tstatus = "disabled";\n}};\n\n'
src += '''/* EINT 12 is the chopin SCP sensor data-ready line (kept unmasked for the SCP firmware). On denniz no SCP
 * runs in recovery mode and the line is wired differently: left unmasked it storms (RCU stall in
 * mtk_eint_do_init, watchdog reboot - first denniz boot, 2026-11-14). */
&pio {
	/delete-property/ mediatek,eint-keep-unmasked;
};

'''
src += '''/* USB 2.0 dual role, switched by hand from userspace (/sys/class/usb_role, scripts/usb-mode.sh): no Type-C
 * controller driver (the MT6360 on i2c5 stays off), device mode by default. Never drive VBUS: the OTG boost on
 * denniz is the MP2650 charger's, and in host mode the power comes from a powered hub. */
&{/usb@11201000} {
	dr_mode = "otg";
	usb-role-switch;
	role-switch-default-mode = "peripheral";
	/delete-property/ vbus-supply;
};

'''
if TYPEC:
    src += '''/* MT6360 Type-C port controller (mainline tcpci_mt6360 + TCPM) on i2c5: CC detection drives the
 * usb@11201000 role switch (OTG hub -> host, PC -> device). Only the TCPC: the MT6360 charger stays off (denniz
 * charges with the MP2650), and the port is a power SINK only - it never sources VBUS (a hub must be powered).
 * The vendor-style children at 0x1a/0x64/0x4e are off: the mt6360 MFD claims those addresses itself. */
&i2c5 {
	status = "okay";
};
&{/i2c5@11F00000/subpmic@34/charger} {
	status = "disabled";
};
&{/i2c5@11F00000/subpmic@34/tcpc/connector} {
	power-role = "sink";
	/delete-property/ try-power-role;
	/delete-property/ source-pdos;
	/* 5 V only (the tree also offered 9/12 V: the hub then cut VBUS mid-transition). 5 V 3 A, USB comm +
	 * dual-role data capable, so a PD hub can swap us to host. */
	sink-pdos = <0x0601912c>;
	op-sink-microwatt = <15000000>;
};
&{/i2c5@11F00000/usb_type_c@4e} {
	status = "disabled";
};
&{/i2c5@11F00000/subpmic_pmic@1a} {
	status = "disabled";
};
&{/i2c5@11F00000/subpmic_ldo@64} {
	status = "disabled";
};

'''
# denniz battery fuel gauge at 0x55 on i2c7 (11d03000), per the phone's own tree: node "oplus,bq27541-battery"
# but flagged qcom,batt_bq28z610 (a TI bq28z610), bus at 100 kHz. Read-only for the kernel (mainline
# bq27xxx_battery). The chopin children of i2c7 (NFC, camera LDO) are not on denniz; 0x68 is the charge pump.
for child in ['st21nfc@08', 'nfc@08', 'willsemi,ldo@28']:
    assert re.search(rf'^\t\t{re.escape(child)} \{{', src, re.M), child
src += '''/* Fuel gauge: TI bq28z610 on i2c7 at 0x55, 100 kHz (from denniz's own tree). */
&i2c7 {
	status = "okay";
	clock-frequency = <100000>;
	/delete-node/ st21nfc@08;
	/delete-node/ nfc@08;
	/delete-node/ willsemi,ldo@28;

	battery@55 {
		compatible = "ti,bq28z610";
		reg = <0x55>;
	};
};
'''
# i2c10..13 (FIFO-only controllers): the vendor clock indices are off by one against the mainline
# imp_iic_wrap_c binding (vendor 2..5 = mainline AP_I2C11..AP_I2C13+1), so each bus gated its neighbour's
# clock and every transfer timed out (seen on i2c11 = MP2650, 2026-11-16). Mainline ids: I2C10=1 .. I2C13=4.
for n, cid in [(10, 1), (11, 2), (12, 3), (13, 4)]:
    assert re.search(rf'\bi2c{n}: i2c{n}@', src + open(chopin.replace('mt6893-xiaomi-chopin.dts', 'mt6893.dtsi')).read()), n
    src += f'&i2c{n} {{\n\tclocks = <&imp_iic_wrap_c {cid}>;\n}};\n\n'
if DISPLAY:
    assert re.search(r'^\t\tpanel@0 \{\n\t\t\tcompatible = "l16_36_02_0b_dsc_vdo,lcm";', src, re.M)
    assert re.search(r'\bmtkfb: mtkfb \{', src)
    assert 'force_no_prim_dual_pipe;' in open(chopin.replace('mt6893-xiaomi-chopin.dts', 'mt6893.dtsi')).read()
    src += '''/* Display: Samsung AMS643YE05 cmd-mode DSC panel on DSI0 (driver panel-oneplus-denniz-ams643ye05). The chopin
 * panel@0 node is reused for its of_graph endpoint; reset is GPIO 42 on both boards. Power rails stay as LK left
 * them, so no supplies here; brightness is DCS 0x51, so no backlight phandle. The chopin mtkfb pinctrl states
 * (LCD bias/reset/TE GPIOs of the Xiaomi board) are dropped: denniz's TE (GPIO 41 mode 1) is muxed by LK. */
&dsi0 {
	status = "okay";
	panel@0 {
		compatible = "oneplus,denniz-ams643ye05";
		/delete-property/ dvdd-supply;
		/delete-property/ backlight;
	};
};

/* LK drives the panel with two pipes of 540 px (OVL0+OVL1 -> merge -> DSC); chopin forces a single pipe. */
&dispsys_config {
	/delete-property/ force_no_prim_dual_pipe;
};

&mtkfb {
	/delete-property/ pinctrl-names;
	/delete-property/ pinctrl-0;
	/delete-property/ pinctrl-1;
	/delete-property/ pinctrl-2;
	/delete-property/ pinctrl-3;
	/delete-property/ pinctrl-4;
	/delete-property/ pinctrl-5;
	/delete-property/ pinctrl-6;
};

'''
open(out, 'w').write(src)
print('wrote', out)
