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
import re, sys

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

# chopin simplefb (LK video-mode panel) off: denniz has a command-mode panel (samsung ams643ye05)
src, n = re.subn(r'(framebuffer@78e0c000 \{.*?status = )"okay"', r'\1"disabled"', src, count=1, flags=re.S); assert n == 1

src += '''
/* ===================== denniz: first-boot overrides ===================== */
/* Board devices of the Xiaomi handset (or unknown wiring on denniz): off. */
'''
for lab in ['i2c0', 'i2c2', 'i2c4', 'i2c5', 'i2c6', 'i2c7', 'i2c8', 'i2c9', 'spi0', 'spi1', 'spi5', 'dsi0',
            'xiaomi_touch', 'cp_qc30', 'usbpd_pm', 'sensor_hub', 'scp_start']:
    assert re.search(rf'\b{lab}:', src + open(chopin.replace('mt6893-xiaomi-chopin.dts', 'mt6893.dtsi')).read()), lab
    src += f'&{lab} {{\n\tstatus = "disabled";\n}};\n\n'
src += '''/* EINT 12 is the chopin SCP sensor data-ready line (kept unmasked for the SCP firmware). On denniz no SCP
 * runs in recovery mode and the line is wired differently: left unmasked it storms (RCU stall in
 * mtk_eint_do_init, watchdog reboot - first denniz boot, 2026-11-14). */
&pio {
	/delete-property/ mediatek,eint-keep-unmasked;
};

'''
src += '''/* USB 2.0 device mode only: no role switch, never drive the MT6360 OTG boost. */
&{/usb@11201000} {
	dr_mode = "peripheral";
	/delete-property/ usb-role-switch;
	/delete-property/ role-switch-default-mode;
	/delete-property/ vbus-supply;
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
open(out, 'w').write(src)
print('wrote', out)
