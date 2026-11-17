#!/usr/bin/env python3
"""Add the denniz panel driver (kernel/panel-oneplus-denniz-ams643ye05.c) to the kernel tree.

Copies the driver into drivers/gpu/drm/panel/, adds Kconfig DRM_PANEL_ONEPLUS_DENNIZ and the Makefile rule
(same include paths as the chopin panel, which uses the same mediatek_v2 mtk_panel_ext API). Idempotent.
Usage: patch-display.py <kernel tree> <repo dir>
"""
import sys, pathlib, shutil

K = pathlib.Path(sys.argv[1]); R = pathlib.Path(sys.argv[2])
P = K / "drivers/gpu/drm/panel"
shutil.copy(R / "kernel/panel-oneplus-denniz-ams643ye05.c", P / "panel-oneplus-denniz-ams643ye05.c")

kc = (P / "Kconfig").read_text()
if "DRM_PANEL_ONEPLUS_DENNIZ" not in kc:
    anchor = "config DRM_PANEL_K10A_36_02_0A\n"
    assert kc.count(anchor) == 1
    kc = kc.replace(anchor, """config DRM_PANEL_ONEPLUS_DENNIZ
	tristate "OnePlus Nord 2 (denniz) Samsung AMS643YE05 DSI panel"
	depends on OF
	depends on DRM_MIPI_DSI
	depends on DRM_MEDIATEK_V2
	depends on BACKLIGHT_CLASS_DEVICE
	help
	  Samsung AMS643YE05 1080x2400 AMOLED, 4-lane MIPI-DSI command mode
	  with DSC, as found on the OnePlus Nord 2 5G (denniz, MT6893).

""" + anchor)
    (P / "Kconfig").write_text(kc)

mk = (P / "Makefile").read_text()
if "panel-oneplus-denniz-ams643ye05.o" not in mk:
    mk += ("\n# denniz panel (mediatek_v2 mtk_panel_ext API)\n"
           "obj-$(CONFIG_DRM_PANEL_ONEPLUS_DENNIZ) += panel-oneplus-denniz-ams643ye05.o\n"
           "CFLAGS_panel-oneplus-denniz-ams643ye05.o += -I$(srctree)/drivers/gpu/drm/mediatek/mediatek_v2 "
           "-I$(srctree)/drivers/misc/mediatek/include -I$(srctree)/drivers/misc/mediatek/include/mt-plat "
           "-I$(srctree)/drivers/misc/mediatek/mmp -I$(srctree)/drivers/misc/mediatek/smi "
           "-I$(srctree)/drivers/misc/mediatek/cmdq/mailbox -I$(srctree)/drivers/misc/mediatek/iommu "
           "-I$(srctree)/drivers/misc/mediatek/slbc -I$(srctree)/drivers/misc/mediatek/mminfra "
           "-I$(srctree)/drivers/misc/mediatek/mtk-interconnect -I$(srctree)/drivers/misc/mediatek/vcp/include "
           "-I$(srctree)/drivers/misc/mediatek/base/power/include\n")
    (P / "Makefile").write_text(mk)
print("display patch applied")
