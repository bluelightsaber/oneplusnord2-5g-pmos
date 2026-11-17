#!/usr/bin/env python3
"""mediatek_v2: CPU frame trigger for command-mode panels when there is no GCE (mtk_cmdq_dummy.c).

In command mode the panel only shows a new frame when the display path is triggered (mutex enable + DSI start).
The vendor driver does that from a GCE "trigger loop" (wait TE -> trigger -> wait EOF, forever). With the CMDQ
dummy used by this tree the loop packet is built once (its register writes execute immediately) and never runs
again, so the panel would keep its first frame. This adds a delayed_work that re-triggers the path at a fixed
rate while the CRTC is in frame-trigger mode: EOF bookkeeping for the previous frame, PRE_TRIGGER, mutex
enable, TRIGGER - the same sequence and helpers as the GCE loop, skipped while the path is still busy.
Rate: denniz_trig_hz (module param of mediatek-drm, default 10; 0 = off). Idempotent.
Usage: patch-display-cputrig.py <kernel tree>
"""
import sys, pathlib

K = pathlib.Path(sys.argv[1])
f = K / "drivers/gpu/drm/mediatek/mediatek_v2/mtk_drm_crtc.c"
s = f.read_text()
MARK = "denniz: CPU frame trigger"
if MARK in s:
    print("already patched"); sys.exit(0)

code = r'''
/* denniz: CPU frame trigger (no GCE: mtk_cmdq_dummy.c) for command-mode panels. */
static unsigned int denniz_trig_hz = 10;
module_param(denniz_trig_hz, uint, 0644);
MODULE_PARM_DESC(denniz_trig_hz, "cmd-mode CPU frame trigger rate in Hz (0 = off)");
static struct mtk_drm_crtc *denniz_trig_crtc;
static bool denniz_trig_pending_eof;
static void denniz_trig_fn(struct work_struct *w);
static DECLARE_DELAYED_WORK(denniz_trig_work, denniz_trig_fn);

static void denniz_trig_fn(struct work_struct *w)
{
	struct mtk_drm_crtc *mtk_crtc = READ_ONCE(denniz_trig_crtc);
	unsigned int hz = READ_ONCE(denniz_trig_hz);

	if (!mtk_crtc)
		return;
	if (hz && mtk_crtc->enabled && !mtk_crtc_comp_is_busy(mtk_crtc)) {
		if (denniz_trig_pending_eof)
			mtk_crtc_comp_trigger(mtk_crtc, NULL, MTK_TRIG_FLAG_EOF);
		mtk_crtc_comp_trigger(mtk_crtc, NULL, MTK_TRIG_FLAG_PRE_TRIGGER);
		mtk_disp_mutex_enable_cmdq(mtk_crtc->mutex[0], NULL, mtk_crtc->gce_obj.base);
		mtk_crtc_comp_trigger(mtk_crtc, NULL, MTK_TRIG_FLAG_TRIGGER);
		denniz_trig_pending_eof = true;
	}
	schedule_delayed_work(&denniz_trig_work, msecs_to_jiffies(hz ? 1000 / hz : 500));
}

static void denniz_trig_start(struct drm_crtc *crtc)
{
	if (drm_crtc_index(crtc) != 0 || !mtk_crtc_is_frame_trigger_mode(crtc))
		return;
	WRITE_ONCE(denniz_trig_crtc, to_mtk_crtc(crtc));
	denniz_trig_pending_eof = false;
	pr_info("denniz: CPU frame trigger on, %u Hz\n", denniz_trig_hz);
	mod_delayed_work(system_wq, &denniz_trig_work, msecs_to_jiffies(50));
}

static void denniz_trig_stop(struct drm_crtc *crtc)
{
	if (READ_ONCE(denniz_trig_crtc) != to_mtk_crtc(crtc))
		return;
	WRITE_ONCE(denniz_trig_crtc, NULL);
	cancel_delayed_work_sync(&denniz_trig_work);
	pr_info("denniz: CPU frame trigger off\n");
}

void mtk_crtc_start_trig_loop(struct drm_crtc *crtc)
{'''

a = "\nvoid mtk_crtc_start_trig_loop(struct drm_crtc *crtc)\n{"
assert s.count(a) == 1, "start_trig_loop anchor"
s = s.replace(a, code)

b = "\tmtk_crtc->trig_loop_cmdq_handle = cmdq_pkt_create(\n\t\tmtk_crtc->gce_obj.client[CLIENT_TRIG_LOOP]);"
assert s.count(b) == 1, "pkt_create anchor"
s = s.replace(b, "\tdenniz_trig_start(crtc);\n" + b)

c = "void mtk_crtc_stop_trig_loop(struct drm_crtc *crtc)\n{\n\tstruct mtk_drm_crtc *mtk_crtc = to_mtk_crtc(crtc);\n"
assert s.count(c) == 1, "stop anchor"
s = s.replace(c, c + "\n\tdenniz_trig_stop(crtc);\n")

# also hook CRTC enable/stop directly: the GCE trigger-loop client may not exist at all without CMDQ
d = "\t/* 4. start trigger loop first to keep gce alive */\n"
assert s.count(d) == 1, "enable anchor"
s = s.replace(d, "\tdenniz_trig_start(crtc);\n" + d)
e = "\t/* 6. stop trig loop  */\n"
assert s.count(e) == 1, "stop-path anchor"
s = s.replace(e, "\tdenniz_trig_stop(&mtk_crtc->base);\n" + e)
# the CRTC adopted from LK is already "enabled" at bind, so enable() takes the skip branch: start there too
g = '\t\tDDPINFO("crtc%d skip %s\\n", crtc_id, __func__);\n\t\tgoto end;\n'
assert s.count(g) >= 1, "skip anchor"
s = s.replace(g, '\t\tDDPINFO("crtc%d skip %s\\n", crtc_id, __func__);\n\t\tdenniz_trig_start(crtc);\n\t\tgoto end;\n', 1)
f.write_text(s)
print("patched", f)
