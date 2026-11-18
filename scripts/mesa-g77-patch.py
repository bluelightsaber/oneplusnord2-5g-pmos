#!/usr/bin/env python3
"""Patch a Mesa 26.x source tree for the denniz Mali-G77 (idempotent). Usage: mesa-g77-patch.py MESA_SRC

1) panfrost model table: add the Mali-G77 (gpu_id 0x9080 = PAN_PROD_ID(9,0,0)); stock Mesa only knows its G57
   derivatives (9.0.1 / 9.0.3), so the GPU fell back to llvmpipe. Idea from MT6891-Mainline/mesa commit 522df1c.
2) v9 Job Manager compute jobs: Mesa always used task_axis=Z / task_increment=1, so a dispatch with grid Z=1
   is a single task and runs on ONE shader core (measured 19 GFLOPS = one G77 core at 350 MHz). Split the job
   into tasks the same way the CSF path (pan_csf.c) does.
3) gallium panfrost: advertise compute subgroups on Valhall (v9+; 16 lanes). The shared Bifrost/Valhall compiler
   already lowers all subgroup ops (PanVK exposes them), but the gallium screen left max_subgroups and the
   shader_subgroup_* caps at 0, so Rusticl had no __opencl_c_subgroups (needed e.g. by ggml's OpenCL backend).
   Compute stage only, so GL fragment/vertex behaviour is unchanged.
"""
import sys
root = sys.argv[1]

def patch(rel, old, new, marker):
    p = f'{root}/{rel}'; s = open(p).read()
    if marker in s:
        print('already', rel); return
    assert s.count(old) == 1, (rel, s.count(old))
    open(p, 'w').write(s.replace(old, new)); print('patched', rel)

g57 = '   VALHALL_MODEL(PAN_PROD_ID(9, 0, 1), 0, "G57",'
patch('src/panfrost/model/pan_model.c', g57,
      '   /* Mali-G77 (MT6893/MT6891, gpu_id 0x9080): first Valhall, same core as the G57 below. */\n'
      '   VALHALL_MODEL(PAN_PROD_ID(9, 0, 0), 0, "G77",    "G77", MODEL_ANISO(ALL),  MODEL_TB_SIZES(16384,  8192),\n'
      '                                              MODEL_RATES_X(2, 4, 8,  32,  32, 8)),\n' + g57,
      'PAN_PROD_ID(9, 0, 0)')

old = ('      cfg.allow_merging_workgroups = cs->info.cs.allow_merging_workgroups &&\n'
       '                                     (info->variable_shared_mem == 0);\n\n'
       '      cfg.task_increment = 1;\n      cfg.task_axis = MALI_TASK_AXIS_Z;\n')
split = '''      /* denniz: split compute jobs into tasks across all shader cores (as the
       * CSF path does) instead of one task per Z slice. */
      cfg.task_increment = 1;
      cfg.task_axis = MALI_TASK_AXIS_Z;
      if (!info->indirect) {
         struct panfrost_device *dev = pan_device(ctx->base.screen);
         unsigned threads_per_task = info->block[0] * info->block[1] * info->block[2];
         unsigned max_thread_cnt = pan_compute_max_thread_count(
            &dev->kmod.dev->props, cs->info.work_reg_count);
         unsigned axis = MALI_TASK_AXIS_X, inc = 0;
         for (unsigned i = 0; i < 3; i++) {
            if (threads_per_task * info->grid[i] >= max_thread_cnt) {
               inc = MAX2(max_thread_cnt / threads_per_task, 1);
               break;
            } else if (axis == MALI_TASK_AXIS_Z) {
               inc = info->grid[i];
               break;
            }
            threads_per_task *= info->grid[i];
            axis++;
         }
         cfg.task_axis = axis;
         cfg.task_increment = MAX2(inc, 1);
      }
'''
patch('src/gallium/drivers/panfrost/pan_jm.c', old,
      old.replace('      cfg.task_increment = 1;\n      cfg.task_axis = MALI_TASK_AXIS_Z;\n', split),
      'denniz: split compute')

cc_old = '   caps->max_threads_per_block = dev->arch >= 6 ? 256 : 128;\n'
patch('src/gallium/drivers/panfrost/pan_screen.c', cc_old,
      cc_old + '   /* denniz: subgroups for compute on Valhall (Rusticl __opencl_c_subgroups) */\n'
      '   if (dev->arch >= 9)\n'
      '      caps->max_subgroups = caps->max_threads_per_block / pan_subgroup_size(dev->arch);\n',
      'denniz: subgroups for compute')
sc_old = '   caps->compute = true;\n   caps->int64 = true;\n'
patch('src/gallium/drivers/panfrost/pan_screen.c', sc_old,
      sc_old + '   /* denniz: subgroup caps (compute only), same operations PanVK advertises */\n'
      '   if (dev->arch >= 9) {\n'
      '      caps->shader_subgroup_size = pan_subgroup_size(dev->arch);\n'
      '      caps->shader_subgroup_supported_stages = BITFIELD_BIT(MESA_SHADER_COMPUTE);\n'
      '      caps->shader_subgroup_supported_features =\n'
      '         PIPE_SHADER_SUBGROUP_FEATURE_BASIC | PIPE_SHADER_SUBGROUP_FEATURE_VOTE |\n'
      '         PIPE_SHADER_SUBGROUP_FEATURE_ARITHMETIC | PIPE_SHADER_SUBGROUP_FEATURE_BALLOT |\n'
      '         PIPE_SHADER_SUBGROUP_FEATURE_SHUFFLE | PIPE_SHADER_SUBGROUP_FEATURE_SHUFFLE_RELATIVE |\n'
      '         PIPE_SHADER_SUBGROUP_FEATURE_CLUSTERED;\n'
      '   }\n',
      'denniz: subgroup caps')
