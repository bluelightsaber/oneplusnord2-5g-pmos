#!/usr/bin/env python3
"""gen4m (CONNAC2 soc3_0): install the station-mode group key (GTK) in WTBL[BssIndex].

Observed on denniz (MT6893): with WPA2 the chip silently drops every broadcast/multicast frame from the AP
(LAN hosts cannot ARP the phone). The driver puts the GTK in a free WTBL entry >= 4, but the RX MAC looks up
group-addressed frames in WTBL[BssIndex] (entries 0..3, which the driver reserves "for BIP"):
  - with PMF, the IGTK install leaves WTBL #0 = AP address, RV=1, no cipher  -> frames reach the driver
    flagged cipher-mismatch with ucWlanIdx 0 and are dropped ("Drop plain text during security connection");
  - without PMF, WTBL #0 is empty -> frames are dropped in hardware.
This puts the AIS (station) GTK into WTBL[BssIndex], next to where the IGTK already goes.
Idempotent. Usage: patch-wifi-gtk-wtbl.py <kernel tree>
"""
import sys, pathlib

K = pathlib.Path(sys.argv[1])
f = K / "drivers/misc/mediatek/connectivity/wlan_drv_gen4m/mgmt/privacy.c"
s = f.read_text()
MARK = "denniz: station GTK in WTBL[BssIndex]"
if MARK in s:
    print("already patched")
    sys.exit(0)
old = """	if (ucAlg == CIPHER_SUITE_BIP) {
		ucEntry = ucBssIndex;
	} else {"""
new = """	if (ucAlg == CIPHER_SUITE_BIP) {
		ucEntry = ucBssIndex;
	} else if (fgCheckKeyId && IS_BSS_AIS(prBSSInfo) &&
		   prBSSInfo->eCurrentOPMode == OP_MODE_INFRASTRUCTURE &&
		   ucBssIndex < ucStartIDX) {
		/* denniz: station GTK in WTBL[BssIndex]: the RX MAC looks
		 * up group-addressed frames there, not in the BMC entry.
		 */
		ucEntry = ucBssIndex;
		DBGLOG(RSN, INFO, "[Wlan index] AIS GTK keyid#%d -> #%d\\n",
		       ucKeyId, ucEntry);
	} else {"""
assert s.count(old) == 1, "anchor not found"
s = s.replace(old, new)
f.write_text(s)
print("patched", f)
