// SPDX-License-Identifier: GPL-2.0
/*
 * denniz-lkfb: keep the bootloader's display pipeline alive for a simple-framebuffer console.
 *
 * On the OnePlus Nord 2 5G (denniz, MT6893) LK leaves the whole display path configured and running: two
 * 540 px pipes (OVL0_2L/OVL1_2L layer 0 on the LK framebuffer 0x78810000, pitch 4352, a8r8g8b8; OVL0/OVL1 layer 1
 * on a logo overlay at 0x79206000), merge, DSC, DSI0 to a Samsung AMS643YE05 command-mode panel. The kernel
 * leaves the display clocks and power domains on (clk_ignore_unused, pd_ignore_unused) and no display driver
 * touches the hardware, so a simple-framebuffer node on 0x78810000 (simpledrm) can draw into the buffer the
 * pipeline scans out. But a command-mode panel only refreshes when a frame is pushed: this driver does that from
 * the CPU at a fixed rate (default 2 Hz) - DSI_INTSTA clear, MUTEX0 enable (single-shot, self-clearing), DSI_START 0 -> 1 - the
 * sequence LK itself uses, skipped while the DSI is still busy. Measured: FRAME_DONE about 10 ms after a trigger.
 *
 * It refuses to run unless the path looks like LK's (DSI0 in command mode, MUTEX0 has modules routed). It also
 * clears the logo overlay buffer once so nothing covers the console. Rate: denniz_lkfb.hz (0 = stop).
 */
#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/jiffies.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/workqueue.h>

#define DSI0_BASE	0x1400e000
#define DSI_START	0x00
#define DSI_INTSTA	0x0c
#define DSI_MODE_CTRL	0x14
#define DSI_BUSY	BIT(31)
#define DSI_FRAME_DONE	BIT(4)
#define MUTEX_BASE	0x14117000
#define MUTEX0_EN	0x20
#define MUTEX0_MOD	0x30
#define LOGO_BASE	0x79206000	/* LK logo overlay (OVL0/OVL1 layer 1), pitch 4320 */
#define LOGO_SIZE	(4320 * 2400)

static unsigned int hz = 2;	/* btop refreshes every 1-2 s; each push re-sends the whole frame */
module_param(hz, uint, 0644);
MODULE_PARM_DESC(hz, "frame push rate in Hz (0 = stop)");
static bool clear_logo = true;
module_param(clear_logo, bool, 0444);
MODULE_PARM_DESC(clear_logo, "clear LK's logo overlay layer at start");

static void __iomem *dsi, *mutex;
static unsigned long frames, skipped;
module_param(frames, ulong, 0444);
module_param(skipped, ulong, 0444);

static void lkfb_push(struct work_struct *w);
static DECLARE_DELAYED_WORK(lkfb_work, lkfb_push);

static void lkfb_push(struct work_struct *w)
{
	unsigned int rate = READ_ONCE(hz);

	if (rate) {
		if (readl(dsi + DSI_INTSTA) & DSI_BUSY) {
			skipped++;
		} else {
			writel(0, dsi + DSI_INTSTA);
			writel(1, mutex + MUTEX0_EN);
			writel(0, dsi + DSI_START);
			writel(1, dsi + DSI_START);
			frames++;
		}
	}
	schedule_delayed_work(&lkfb_work, msecs_to_jiffies(rate ? 1000 / min(rate, 60U) : 1000));
}

static int __init lkfb_init(void)
{
	u32 mode, mod;

	dsi = ioremap(DSI0_BASE, 0x1000);
	mutex = ioremap(MUTEX_BASE, 0x1000);
	if (!dsi || !mutex)
		goto fail;
	mode = readl(dsi + DSI_MODE_CTRL);
	mod = readl(mutex + MUTEX0_MOD);
	if ((mode & 3) != 0 || !mod) {
		pr_warn("denniz-lkfb: display path not left by LK (DSI mode %#x, mutex0 mod %#x), not starting\n",
			mode, mod);
		goto fail;
	}
	if (clear_logo) {
		void *logo = memremap(LOGO_BASE, LOGO_SIZE, MEMREMAP_WC);

		if (logo) {
			memset(logo, 0, LOGO_SIZE);
			wmb();
			memunmap(logo);
		}
	}
	pr_info("denniz-lkfb: pushing LK pipeline frames at %u Hz (mutex0 mod %#x)\n", hz, mod);
	schedule_delayed_work(&lkfb_work, msecs_to_jiffies(100));
	return 0;
fail:
	if (dsi)
		iounmap(dsi);
	if (mutex)
		iounmap(mutex);
	return 0;	/* never fail the boot */
}
late_initcall(lkfb_init);

MODULE_DESCRIPTION("denniz: push frames through the LK-configured display pipeline");
MODULE_LICENSE("GPL");
