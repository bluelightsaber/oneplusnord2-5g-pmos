/* cl-bench.c: minimal OpenCL correctness + throughput check (denniz Mali-G77 via Mesa rusticl).
 * Tiled SGEMM (fp32) and HGEMM-in-fp16 storage with fp32 accumulate, checked against the CPU.
 * Build: cc -O2 -o cl-bench cl-bench.c -lOpenCL -lm    Run: cl-bench [N=1024]
 */
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define CK(x) do { cl_int e_ = (x); if (e_ != CL_SUCCESS) { fprintf(stderr, "%s:%d %s = %d\n", __FILE__, __LINE__, #x, e_); exit(1); } } while (0)

static const char *src =
"#define T 16\n"
"__kernel void naive(int n, __global const float *a, __global const float *b, __global float *c) {\n"
"  int gr = get_global_id(1), gc = get_global_id(0); float acc = 0.f;\n"
"  for (int k = 0; k < n; k++) acc += a[gr * n + k] * b[k * n + gc];\n"
"  c[gr * n + gc] = acc;\n"
"}\n"
"__kernel void sgemm(int n, __global const float *a, __global const float *b, __global float *c) {\n"
"  int r = get_local_id(1), q = get_local_id(0), gr = get_global_id(1), gc = get_global_id(0);\n"
"  __local float as[T][T], bs[T][T]; float acc = 0.f;\n"
"  for (int t = 0; t < n; t += T) {\n"
"    as[r][q] = a[gr * n + t + q]; bs[r][q] = b[(t + r) * n + gc];\n"
"    barrier(CLK_LOCAL_MEM_FENCE);\n"
"    for (int k = 0; k < T; k++) acc += as[r][k] * bs[k][q];\n"
"    barrier(CLK_LOCAL_MEM_FENCE);\n"
"  }\n"
"  c[gr * n + gc] = acc;\n"
"}\n"
"#pragma OPENCL EXTENSION cl_khr_fp16 : enable\n"
"__kernel void hgemm(int n, __global const half *a, __global const half *b, __global float *c) {\n"
"  int r = get_local_id(1), q = get_local_id(0), gr = get_global_id(1), gc = get_global_id(0);\n"
"  __local half as[T][T], bs[T][T]; float acc = 0.f;\n"
"  for (int t = 0; t < n; t += T) {\n"
"    as[r][q] = a[gr * n + t + q]; bs[r][q] = b[(t + r) * n + gc];\n"
"    barrier(CLK_LOCAL_MEM_FENCE);\n"
"    for (int k = 0; k < T; k++) acc += (float)as[r][k] * (float)bs[k][q];\n"
"    barrier(CLK_LOCAL_MEM_FENCE);\n"
"  }\n"
"  c[gr * n + gc] = acc;\n"
"}\n";

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static unsigned short f2h(float f) { /* round-to-nearest fp32 -> fp16 for small normal values */
	unsigned int x = *(unsigned int *)&f, s = (x >> 16) & 0x8000; int e = ((x >> 23) & 0xff) - 127 + 15;
	unsigned int m = x & 0x7fffff; if (e <= 0) return s; if (e >= 31) return s | 0x7c00;
	return s | (e << 10) | ((m + 0x1000) >> 13);
}

int main(int argc, char **argv) {
	int n = argc > 1 ? atoi(argv[1]) : 1024; size_t nn = (size_t)n * n, i;
	cl_platform_id p; cl_device_id d; char name[256]; cl_int e;
	CK(clGetPlatformIDs(1, &p, NULL)); CK(clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
	CK(clGetDeviceInfo(d, CL_DEVICE_NAME, sizeof name, name, NULL)); printf("device: %s, n=%d\n", name, n);
	cl_context ctx = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
	cl_command_queue cq = clCreateCommandQueueWithProperties(ctx, d, NULL, &e); CK(e);
	cl_program pr = clCreateProgramWithSource(ctx, 1, &src, NULL, &e); CK(e);
	double t0 = now();
	if (clBuildProgram(pr, 1, &d, "", NULL, NULL) != CL_SUCCESS) {
		char log[8192]; clGetProgramBuildInfo(pr, d, CL_PROGRAM_BUILD_LOG, sizeof log, log, NULL); fprintf(stderr, "%s\n", log); return 1; }
	printf("build: %.2f s\n", now() - t0);
	float *a = malloc(nn * 4), *b = malloc(nn * 4), *c = malloc(nn * 4);
	unsigned short *ah = malloc(nn * 2), *bh = malloc(nn * 2);
	srand(1); for (i = 0; i < nn; i++) { a[i] = (rand() % 17 - 8) / 8.f; b[i] = (rand() % 17 - 8) / 8.f; ah[i] = f2h(a[i]); bh[i] = f2h(b[i]); }
	cl_mem A = clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, nn * 4, a, &e); CK(e);
	cl_mem B = clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, nn * 4, b, &e); CK(e);
	cl_mem Ah = clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, nn * 2, ah, &e); CK(e);
	cl_mem Bh = clCreateBuffer(ctx, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, nn * 2, bh, &e); CK(e);
	cl_mem C = clCreateBuffer(ctx, CL_MEM_WRITE_ONLY, nn * 4, NULL, &e); CK(e);
	const char *kn[3] = { "naive", "sgemm", "hgemm" };
	for (int v = 0; v < 3; v++) {
		cl_kernel k = clCreateKernel(pr, kn[v], &e); CK(e);
		CK(clSetKernelArg(k, 0, sizeof n, &n)); CK(clSetKernelArg(k, 1, sizeof(cl_mem), v == 2 ? &Ah : &A));
		CK(clSetKernelArg(k, 2, sizeof(cl_mem), v == 2 ? &Bh : &B)); CK(clSetKernelArg(k, 3, sizeof(cl_mem), &C));
		size_t g[2] = { n, n }, l[2] = { 16, 16 };
		CK(clEnqueueNDRangeKernel(cq, k, 2, NULL, g, l, 0, NULL, NULL)); CK(clFinish(cq)); /* warm-up */
		int reps = 5; t0 = now();
		for (int r = 0; r < reps; r++) CK(clEnqueueNDRangeKernel(cq, k, 2, NULL, g, l, 0, NULL, NULL));
		CK(clFinish(cq)); double dt = (now() - t0) / reps;
		CK(clEnqueueReadBuffer(cq, C, CL_TRUE, 0, nn * 4, c, 0, NULL, NULL));
		/* check 64 random entries against the CPU (inputs are exact in fp16, so both must match exactly) */
		int bad = 0; for (int s = 0; s < 64; s++) { size_t r = rand() % n, q = rand() % n; double ref = 0;
			for (int kk = 0; kk < n; kk++) ref += (double)a[r * n + kk] * b[kk * n + q];
			if (fabs(ref - c[r * n + q]) > 1e-3 * (1 + fabs(ref))) bad++; }
		printf("%s: %.1f ms, %.1f GFLOPS, check %s (%d/64 bad)\n", kn[v], dt * 1e3, 2.0 * n * nn / dt / 1e9, bad ? "FAIL" : "OK", bad);
		clReleaseKernel(k);
	}
	return 0;
}
