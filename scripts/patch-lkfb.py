#!/usr/bin/env python3
"""Add kernel/denniz-lkfb.c (LK display pipeline frame pusher) to the kernel tree as CONFIG_DENNIZ_LKFB.
Lives in drivers/soc/mediatek/. Idempotent. Usage: patch-lkfb.py <kernel tree> <repo dir>
"""
import sys, pathlib, shutil
K = pathlib.Path(sys.argv[1]); R = pathlib.Path(sys.argv[2]); D = K / "drivers/soc/mediatek"
shutil.copy(R / "kernel/denniz-lkfb.c", D / "denniz-lkfb.c")
kc = (D / "Kconfig").read_text()
if "DENNIZ_LKFB" not in kc:
    i = kc.rindex("endmenu")
    kc = kc[:i] + """config DENNIZ_LKFB
	bool "OnePlus Nord 2 (denniz): push frames through the bootloader display pipeline"
	depends on ARM64
	help
	  Command-mode panel console without a display driver: periodically
	  triggers the display path LK leaves configured, so a
	  simple-framebuffer (simpledrm) on LK's framebuffer reaches the panel.

""" + kc[i:]
    (D / "Kconfig").write_text(kc)
mk = (D / "Makefile").read_text()
if "denniz-lkfb.o" not in mk:
    (D / "Makefile").write_text(mk + "obj-$(CONFIG_DENNIZ_LKFB) += denniz-lkfb.o\n")
print("lkfb patch applied")
