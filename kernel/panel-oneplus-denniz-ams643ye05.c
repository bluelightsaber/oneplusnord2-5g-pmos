// SPDX-License-Identifier: GPL-2.0-only
/*
 * Samsung AMS643YE05 1080x2400 AMOLED, MIPI DSI command mode with DSC 1.1
 * (OnePlus Nord 2 5G, "denniz", MT6893), for the mediatek_v2 display stack.
 *
 * Panel data (init sequence, timings, DSC parameters, brightness command) are
 * taken from OnePlus' GPL kernel source for this phone:
 *   OnePlusOSS/android_kernel_oneplus_mt6893, branch oneplus/MT6893_R_11.0,
 *   drivers/gpu/drm/panel/oplus20615_samsung_ams643ye05_1080p_dsi_cmd.c
 * reduced to what a headless server needs: no HBM/AOD/fingerprint/ESD/seed
 * paths, no round corners, 60 Hz only.
 *
 * Power: the bootloader (LK) powers and initialises the panel before Linux
 * starts and this driver adopts that state, as the vendor driver does
 * (prepared/enabled = true at probe). The rails (VMC 3.0 V and an external
 * OLED PMIC LDO) are never switched here: blanking uses DCS display off +
 * sleep in, unblanking sleep out + the full init sequence.
 */
#include <linux/backlight.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_graph.h>
#include <drm/drm_connector.h>
#include <drm/drm_device.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <video/mipi_display.h>

#define CONFIG_MTK_PANEL_EXT
#include "../mediatek/mediatek_v2/mtk_panel_ext.h"
#include "../mediatek/mediatek_v2/mtk_drm_graphics_base.h"

#define FRAME_WIDTH		1080
#define FRAME_HEIGHT		2400
#define PHYSICAL_WIDTH_UM	68040
#define PHYSICAL_HEIGHT_UM	151200
#define DATA_RATE		600	/* Mbps per lane, 4 lanes */
#define MAX_BRIGHTNESS		2047	/* normal range of DCS 0x51 (11 bit) */
#define DEFAULT_BRIGHTNESS	600

struct denniz_panel {
	struct device *dev;
	struct drm_panel panel;
	struct backlight_device *bl;
	struct gpio_desc *reset_gpio;
	bool prepared;
	bool enabled;
	int error;
};

static inline struct denniz_panel *to_dp(struct drm_panel *panel)
{
	return container_of(panel, struct denniz_panel, panel);
}

static void dp_write(struct denniz_panel *ctx, const u8 *data, size_t len)
{
	struct mipi_dsi_device *dsi = to_mipi_dsi_device(ctx->dev);
	ssize_t ret;

	if (ctx->error < 0)
		return;
	if (data[0] < 0xB0)
		ret = mipi_dsi_dcs_write_buffer(dsi, data, len);
	else
		ret = mipi_dsi_generic_write(dsi, data, len);
	if (ret < 0) {
		dev_err(ctx->dev, "error %zd writing %*ph\n", ret, (int)min_t(size_t, len, 8), data);
		ctx->error = ret;
	}
}

#define dp_seq(ctx, seq...) ({ static const u8 d[] = { seq }; dp_write(ctx, d, ARRAY_SIZE(d)); })

/* Vendor lcm_panel_init(), DCI-P3 seed branch (the vendor default). */
static void dp_init_sequence(struct denniz_panel *ctx)
{
	/* DSC PPS */
	dp_seq(ctx, 0x9E, 0x11, 0x00, 0x00, 0x89, 0x30, 0x80, 0x09, 0x60, 0x04, 0x38,
		0x00, 0x1E, 0x02, 0x1C, 0x02, 0x1C, 0x02, 0x00, 0x02, 0x0E,
		0x00, 0x20, 0x02, 0xE3, 0x00, 0x07, 0x00, 0x0C, 0x03, 0x50,
		0x03, 0x64, 0x18, 0x00, 0x10, 0xF0, 0x03, 0x0C, 0x20, 0x00,
		0x06, 0x0B, 0x0B, 0x33, 0x0E, 0x1C, 0x2A, 0x38, 0x46, 0x54,
		0x62, 0x69, 0x70, 0x77, 0x79, 0x7B, 0x7D, 0x7E, 0x01, 0x02,
		0x01, 0x00, 0x09, 0x40, 0x09, 0xBE, 0x19, 0xFC, 0x19, 0xFA,
		0x19, 0xF8, 0x1A, 0x38, 0x1A, 0x78, 0x1A, 0xB6, 0x2A, 0xF6,
		0x2B, 0x34, 0x2B, 0x74, 0x3B, 0x74, 0x6B, 0xF4, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
	dp_seq(ctx, 0xC2, 0x14);
	dp_seq(ctx, 0x9D, 0x01);
	dp_seq(ctx, MIPI_DCS_EXIT_SLEEP_MODE);
	msleep(10);
	/* DC-DC (SM3010) power control */
	dp_seq(ctx, 0xF0, 0x5A, 0x5A);
	dp_seq(ctx, 0xB0, 0x01, 0x63);
	dp_seq(ctx, 0x63, 0x13);
	dp_seq(ctx, 0xF0, 0xA5, 0xA5);
	msleep(85);
	/* colour "seed": DCI-P3 */
	dp_seq(ctx, 0xF0, 0x5A, 0x5A);
	dp_seq(ctx, 0x5D, 0x86);
	dp_seq(ctx, 0x62, 0x00);
	dp_seq(ctx, 0xB0, 0x2B, 0x62);
	dp_seq(ctx, 0x62, 0xD8, 0x00, 0x04, 0x00, 0xFF, 0x02, 0x00, 0x00, 0xFF, 0x18, 0xFF,
		0xE4, 0xFB, 0x00, 0xF0, 0xF6, 0xEA, 0x01, 0xFF, 0xFF, 0xFF);
	dp_seq(ctx, 0xF0, 0xA5, 0xA5);
	msleep(20);
	dp_seq(ctx, MIPI_DCS_SET_TEAR_ON, 0x00);
	dp_seq(ctx, MIPI_DCS_SET_COLUMN_ADDRESS, 0x00, 0x00, 0x04, 0x37);
	dp_seq(ctx, MIPI_DCS_SET_PAGE_ADDRESS, 0x00, 0x00, 0x09, 0x5F);
	/* FQ CON */
	dp_seq(ctx, 0xF0, 0x5A, 0x5A);
	dp_seq(ctx, 0xB0, 0x27, 0xF2);
	dp_seq(ctx, 0xF2, 0x00);
	dp_seq(ctx, 0xF0, 0xA5, 0xA5);
	/* 60 Hz */
	dp_seq(ctx, 0xF0, 0x5A, 0x5A);
	dp_seq(ctx, 0x60, 0x00, 0x00);
	dp_seq(ctx, 0xF7, 0x0F);
	dp_seq(ctx, 0xF0, 0xA5, 0xA5);
	/* dimming on, ACL off */
	dp_seq(ctx, MIPI_DCS_WRITE_CONTROL_DISPLAY, 0x20);
	dp_seq(ctx, MIPI_DCS_WRITE_POWER_SAVE, 0x00);
	dp_seq(ctx, MIPI_DCS_SET_DISPLAY_ON);
}

static void dp_reset(struct denniz_panel *ctx)
{
	if (!ctx->reset_gpio)
		return;
	gpiod_set_value(ctx->reset_gpio, 1);
	msleep(10);
	gpiod_set_value(ctx->reset_gpio, 0);
	msleep(2);
	gpiod_set_value(ctx->reset_gpio, 1);
	msleep(10);
}

static int dp_unprepare(struct drm_panel *panel)
{
	struct denniz_panel *ctx = to_dp(panel);

	if (!ctx->prepared)
		return 0;
	dp_seq(ctx, MIPI_DCS_SET_DISPLAY_OFF);
	msleep(10);
	dp_seq(ctx, MIPI_DCS_ENTER_SLEEP_MODE);
	msleep(120);
	ctx->error = 0;
	ctx->prepared = false;
	return 0;
}

static int dp_prepare(struct drm_panel *panel)
{
	struct denniz_panel *ctx = to_dp(panel);
	int ret;

	if (ctx->prepared)
		return 0;
	ctx->error = 0;
	dp_reset(ctx);
	dp_init_sequence(ctx);
	ret = ctx->error;
	if (ret < 0) {
		dev_err(ctx->dev, "init sequence failed: %d\n", ret);
		return ret;
	}
	ctx->prepared = true;
	return 0;
}

static int dp_enable(struct drm_panel *panel)
{
	struct denniz_panel *ctx = to_dp(panel);

	if (ctx->enabled)
		return 0;
	if (ctx->bl) {
		ctx->bl->props.power = BACKLIGHT_POWER_ON;
		backlight_update_status(ctx->bl);
	}
	ctx->enabled = true;
	return 0;
}

static int dp_disable(struct drm_panel *panel)
{
	struct denniz_panel *ctx = to_dp(panel);

	if (!ctx->enabled)
		return 0;
	if (ctx->bl) {
		ctx->bl->props.power = BACKLIGHT_POWER_OFF;
		backlight_update_status(ctx->bl);
	}
	ctx->enabled = false;
	return 0;
}

static const struct drm_display_mode default_mode = {
	.clock = 163530,
	.hdisplay = FRAME_WIDTH,
	.hsync_start = FRAME_WIDTH + 40,
	.hsync_end = FRAME_WIDTH + 40 + 10,
	.htotal = FRAME_WIDTH + 40 + 10 + 20,
	.vdisplay = FRAME_HEIGHT,
	.vsync_start = FRAME_HEIGHT + 20,
	.vsync_end = FRAME_HEIGHT + 20 + 2,
	.vtotal = FRAME_HEIGHT + 20 + 2 + 8,
};

static int dp_get_modes(struct drm_panel *panel, struct drm_connector *connector)
{
	struct drm_display_mode *mode;

	mode = drm_mode_duplicate(connector->dev, &default_mode);
	if (!mode)
		return -ENOMEM;
	drm_mode_set_name(mode);
	mode->type = DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED;
	drm_mode_probed_add(connector, mode);
	connector->display_info.width_mm = PHYSICAL_WIDTH_UM / 1000;
	connector->display_info.height_mm = PHYSICAL_HEIGHT_UM / 1000;
	return 1;
}

static const struct drm_panel_funcs dp_funcs = {
	.disable = dp_disable,
	.unprepare = dp_unprepare,
	.prepare = dp_prepare,
	.enable = dp_enable,
	.get_modes = dp_get_modes,
};

static struct mtk_panel_params ext_params = {
	.pll_clk = DATA_RATE / 2,
	.data_rate = DATA_RATE,
	.output_mode = MTK_PANEL_DSC_SINGLE_PORT,
	.dsc_params = {
		.enable = 1,
		.ver = 17,
		.slice_mode = 1,
		.rgb_swap = 0,
		.dsc_cfg = 34,
		.rct_on = 1,
		.bit_per_channel = 8,
		.dsc_line_buf_depth = 9,
		.bp_enable = 1,
		.bit_per_pixel = 128,
		.pic_height = FRAME_HEIGHT,
		.pic_width = FRAME_WIDTH,
		.slice_height = 30,
		.slice_width = 540,
		.chunk_size = 540,
		.xmit_delay = 512,
		.dec_delay = 526,
		.scale_value = 32,
		.increment_interval = 739,
		.decrement_interval = 7,
		.line_bpg_offset = 12,
		.nfl_bpg_offset = 848,
		.slice_bpg_offset = 868,
		.initial_offset = 6144,
		.final_offset = 4336,
		.flatness_minqp = 3,
		.flatness_maxqp = 12,
		.rc_model_size = 8192,
		.rc_edge_factor = 6,
		.rc_quant_incr_limit0 = 11,
		.rc_quant_incr_limit1 = 11,
		.rc_tgt_offset_hi = 3,
		.rc_tgt_offset_lo = 3,
	},
	.physical_width_um = PHYSICAL_WIDTH_UM,
	.physical_height_um = PHYSICAL_HEIGHT_UM,
};

/* Brightness through the display pipeline (vendor lcm_setbacklight_cmdq, normal range only). */
static int dp_set_backlight_cmdq(void *dsi, dcs_write_gce cb, void *handle, unsigned int level)
{
	char bl[] = { MIPI_DCS_SET_DISPLAY_BRIGHTNESS, 0x00, 0x00 };

	if (!cb)
		return -EINVAL;
	if (level > MAX_BRIGHTNESS)
		level = MAX_BRIGHTNESS;
	if (level > 0 && level < 4)
		level = 4;
	bl[1] = level >> 8;
	bl[2] = level & 0xff;
	cb(dsi, handle, bl, ARRAY_SIZE(bl));
	return 0;
}

static int dp_ext_reset(struct drm_panel *panel, int on)
{
	struct denniz_panel *ctx = to_dp(panel);

	if (ctx->reset_gpio)
		gpiod_set_value(ctx->reset_gpio, on);
	return 0;
}

static struct mtk_panel_funcs ext_funcs = {
	.reset = dp_ext_reset,
	.set_backlight_cmdq = dp_set_backlight_cmdq,
};

/* Backlight class device (sysfs brightness) writing DCS 0x51 directly; used when the DRM pipeline is idle. */
static int dp_bl_update(struct backlight_device *bl)
{
	struct mipi_dsi_device *dsi = bl_get_data(bl);
	int level = backlight_get_brightness(bl);
	u8 d[] = { MIPI_DCS_SET_DISPLAY_BRIGHTNESS, level >> 8, level & 0xff };
	ssize_t ret;

	ret = mipi_dsi_dcs_write_buffer(dsi, d, sizeof(d));
	return ret < 0 ? ret : 0;
}

static const struct backlight_ops dp_bl_ops = {
	.update_status = dp_bl_update,
};

static int dp_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct backlight_properties props = {
		.type = BACKLIGHT_RAW,
		.brightness = DEFAULT_BRIGHTNESS,
		.max_brightness = MAX_BRIGHTNESS,
	};
	struct denniz_panel *ctx;
	int ret;

	ctx = devm_drm_panel_alloc(dev, struct denniz_panel, panel, &dp_funcs,
				   DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);
	mipi_dsi_set_drvdata(dsi, ctx);
	ctx->dev = dev;

	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	/* command mode (no MIPI_DSI_MODE_VIDEO), EoT packets on as in the vendor driver */
	dsi->mode_flags = MIPI_DSI_MODE_LPM | MIPI_DSI_CLOCK_NON_CONTINUOUS;

	/* GPIOD_ASIS: LK left the panel out of reset, do not glitch it */
	ctx->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_ASIS);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio), "reset gpio\n");
	if (ctx->reset_gpio)
		gpiod_direction_output(ctx->reset_gpio, 1);

	/* adopt the state LK left (panel on, initialised, showing its frame) */
	ctx->prepared = true;
	ctx->enabled = true;

	ctx->bl = devm_backlight_device_register(dev, "panel0-backlight", dev, dsi,
						 &dp_bl_ops, &props);
	if (IS_ERR(ctx->bl))
		return dev_err_probe(dev, PTR_ERR(ctx->bl), "backlight\n");

	drm_panel_add(&ctx->panel);

	ret = mipi_dsi_attach(dsi);
	if (ret < 0) {
		dev_err(dev, "mipi_dsi_attach failed %d\n", ret);
		drm_panel_remove(&ctx->panel);
		return ret;
	}

	ret = mtk_panel_ext_create(dev, &ext_params, &ext_funcs, &ctx->panel);
	if (ret < 0) {
		dev_err(dev, "mtk_panel_ext_create failed %d\n", ret);
		return ret;
	}
	dev_info(dev, "AMS643YE05 cmd-mode DSC panel, adopted from LK\n");
	return 0;
}

static void dp_remove(struct mipi_dsi_device *dsi)
{
	struct denniz_panel *ctx = mipi_dsi_get_drvdata(dsi);
	struct mtk_panel_ctx *ext_ctx = find_panel_ctx(&ctx->panel);

	mipi_dsi_detach(dsi);
	drm_panel_remove(&ctx->panel);
	if (ext_ctx) {
		mtk_panel_detach(ext_ctx);
		mtk_panel_remove(ext_ctx);
	}
}

static const struct of_device_id dp_of_match[] = {
	{ .compatible = "oneplus,denniz-ams643ye05" },
	{ }
};
MODULE_DEVICE_TABLE(of, dp_of_match);

static struct mipi_dsi_driver dp_driver = {
	.probe = dp_probe,
	.remove = dp_remove,
	.driver = {
		.name = "panel-oneplus-denniz-ams643ye05",
		.of_match_table = dp_of_match,
	},
};
module_mipi_dsi_driver(dp_driver);

MODULE_DESCRIPTION("Samsung AMS643YE05 (OnePlus Nord 2 denniz) cmd-mode DSC panel");
MODULE_LICENSE("GPL v2");
