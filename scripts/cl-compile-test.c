/* cl-compile-test.c: build one OpenCL C source file on the first GPU device and report the result.
 * Used to find which ggml-opencl kernels crash or fail in Rusticl/clang on the Mali-G77 (one process per file,
 * so a compiler crash only kills that run).  Build: cc -O2 -o cl-compile-test cl-compile-test.c -lOpenCL
 * Run: cl-compile-test FILE.cl "BUILD OPTIONS"
 */
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
	if (argc < 3) { fprintf(stderr, "usage: %s FILE.cl OPTS\n", argv[0]); return 2; }
	FILE *f = fopen(argv[1], "rb"); if (!f) { perror(argv[1]); return 2; }
	fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
	char *src = malloc(n + 1); if (fread(src, 1, n, f) != (size_t)n) return 2; src[n] = 0; fclose(f);
	cl_platform_id p; cl_device_id d; cl_int e;
	if (clGetPlatformIDs(1, &p, NULL) || clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 1, &d, NULL)) { puts("no device"); return 2; }
	cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e);
	cl_program pr = clCreateProgramWithSource(c, 1, (const char **)&src, NULL, &e);
	e = clBuildProgram(pr, 1, &d, argv[2], NULL, NULL);
	if (e != CL_SUCCESS) {
		size_t ls; clGetProgramBuildInfo(pr, d, CL_PROGRAM_BUILD_LOG, 0, NULL, &ls);
		char *log = malloc(ls + 1); clGetProgramBuildInfo(pr, d, CL_PROGRAM_BUILD_LOG, ls, log, NULL); log[ls] = 0;
		printf("FAIL %d\n%.1500s\n", e, log); return 1;
	}
	cl_uint nk = 0; clCreateKernelsInProgram(pr, 0, NULL, &nk);
	printf("OK kernels=%u\n", nk); return 0;
}
