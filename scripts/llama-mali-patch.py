#!/usr/bin/env python3
"""Let ggml's OpenCL backend run on an Arm Mali Valhall GPU through Mesa Rusticl (experimental, idempotent).

ggml-opencl only accepts Adreno and Intel. Valhall's native subgroup size is 16, the size the Intel kernel paths
are written for (REQD_SUBGROUP_SIZE_16, nth0 = 16), and those kernels only use standard cl_khr_subgroups builtins.
So a Mali device is run on the Intel paths, with:
  - detection: device name "Mali" -> GPU_FAMILY::INTEL plus a global g_ggml_cl_mali flag;
  - the cl_khr_subgroups extension-string check skipped (Rusticl exposes only the OpenCL C 3.0 feature
    __opencl_c_subgroups, not the extension, as it lacks independent forward progress);
  - every kernel built with -DGGML_MALI=1; kernels then define INTEL_GPU with empty REQD_SUBGROUP_SIZE_* macros
    (Rusticl has no cl_intel_required_subgroup_size; the subgroup size is fixed at 16 anyway);
  - host-side "subgroup size 32 on Intel" values replaced by 16 on Mali.
Needs Mesa with compute subgroups for panfrost (mesa-g77-patch.py part 3). Validate with test-backend-ops.
Usage: llama-mali-patch.py LLAMA_SRC
"""
import sys, pathlib, re
R = pathlib.Path(sys.argv[1]); D = R / "ggml/src/ggml-opencl"
f = D / "ggml-opencl.cpp"; s = f.read_text()
MARK = "g_ggml_cl_mali"
if MARK in s:
    print("already patched"); sys.exit(0)

def rep(old, new, count=1):
    global s
    n = s.count(old)
    assert n == count, (old[:60], n)
    s = s.replace(old, new)

rep("enum GPU_FAMILY {\n    ADRENO,\n    INTEL,\n    UNKNOWN,\n};\n",
    "enum GPU_FAMILY {\n    ADRENO,\n    INTEL,\n    UNKNOWN,\n};\n\n"
    "// denniz: Arm Mali (Valhall, subgroup 16) runs on the INTEL paths; see llama-mali-patch.py\n"
    "static bool g_ggml_cl_mali = false;\n")
rep('    } else if (strstr(dev_ctx->device_name.c_str(), "Intel")) {\n        dev_ctx->gpu_family = GPU_FAMILY::INTEL;\n',
    '    } else if (strstr(dev_ctx->device_name.c_str(), "Mali")) {\n'
    '        dev_ctx->gpu_family = GPU_FAMILY::INTEL;\n        g_ggml_cl_mali = true;\n'
    '        GGML_LOG_INFO("ggml_opencl: Mali GPU, using the Intel (subgroup 16) kernel paths\\n");\n'
    '    } else if (strstr(dev_ctx->device_name.c_str(), "Intel")) {\n        dev_ctx->gpu_family = GPU_FAMILY::INTEL;\n')
rep('    if (opencl_c_version.major == 3 && strstr(ext_buffer.data(), "cl_khr_subgroups") == NULL &&',
    '    if (opencl_c_version.major == 3 && !g_ggml_cl_mali && strstr(ext_buffer.data(), "cl_khr_subgroups") == NULL &&')
rep("        err = clBuildProgram(p, 0, NULL, compile_opts.c_str(), NULL, NULL);\n",
    "        const std::string opts_mali = g_ggml_cl_mali ? compile_opts + \" -DGGML_MALI=1\" : compile_opts;\n"
    "        err = clBuildProgram(p, 0, NULL, opts_mali.c_str(), NULL, NULL);\n")
# host-side Intel subgroup size 32 -> 16 on Mali
n0 = s.count("INTEL) sgs = 32;")
s = s.replace("INTEL) sgs = 32;", "INTEL) sgs = g_ggml_cl_mali ? 16 : 32;")
s, n1 = re.subn(r"(\} else if \(backend_ctx->gpu_family == INTEL\) \{\n\s+sgs = )32;", r"\1g_ggml_cl_mali ? 16 : 32;", s)
s, n2 = re.subn(r"GPU_FAMILY::INTEL \? 32 : -1", "GPU_FAMILY::INTEL ? (g_ggml_cl_mali ? 16 : 32) : -1", s)
s, n3 = re.subn(r'opts \+= " -D FA_SG=32";', 'opts += g_ggml_cl_mali ? " -D FA_SG=16" : " -D FA_SG=32";', s)
f.write_text(s)
print(f"host: sgs {n0}+{n1}, sg_size {n2}, FA_SG {n3}")

# kernels: Mali branch before the Intel required-subgroup-size branch
k = 0
for cl in sorted((D / "kernels").glob("*.cl")):
    t = cl.read_text()
    old = "#ifdef cl_intel_required_subgroup_size\n"
    if old not in t or "GGML_MALI" in t:
        continue
    fa = "REQD_FA_SG" in t
    t = t.replace(old, "#if defined(GGML_MALI)\n#define INTEL_GPU 1\n#define REQD_SUBGROUP_SIZE_16\n"
                  "#define REQD_SUBGROUP_SIZE_32\n" + ("#define REQD_FA_SG\n" if fa else "") +
                  "#elif defined(cl_intel_required_subgroup_size)\n", 1)
    cl.write_text(t); k += 1
print(f"kernels patched: {k}")
