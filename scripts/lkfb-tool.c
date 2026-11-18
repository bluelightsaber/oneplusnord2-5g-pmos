/* lkfb-tool.c: poke the display pipeline the bootloader (LK) leaves running on denniz (MT6893), via /dev/mem.
 * Research tool for a "reuse LK's pipeline" console: the panel is a command-mode DSI panel, so a new frame only
 * reaches it when the path is triggered (mutex enable + DSI start); LK leaves OVL/RDMA/DSC/DSI configured.
 *   lkfb-tool stat ADDR PITCH W H         rows/cols with non-zero pixels in a 32-bit buffer
 *   lkfb-tool fill ADDR PITCH X Y W H RGBA fill a rectangle
 *   lkfb-tool trig [N] [MS]                N frames (default 1), MS ms apart: clear DSI_INTSTA, MUTEX0 EN=1,
 *                                          DSI_START 0->1, poll INTSTA; prints the status bits seen
 *   lkfb-tool rd ADDR [COUNT]              read 32-bit registers
 *   lkfb-tool dump ADDR PITCH W H FILE [N] [MS]  raw 32-bit snapshot(s) of a buffer to FILE (N frames, MS apart)
 * Build: cc -O2 -o lkfb-tool lkfb-tool.c
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static int fd;
static volatile uint32_t *map(uint64_t pa, size_t len, size_t *off)
{
	uint64_t base = pa & ~0xfffULL; *off = pa - base;
	void *p = mmap(NULL, len + *off, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
	if (p == MAP_FAILED) { perror("mmap"); exit(1); }
	return (volatile uint32_t *)((char *)p + *off);
}
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

#define DSI 0x1400e000ULL
#define MUTEX 0x14117000ULL

int main(int argc, char **argv)
{
	size_t off;
	if (argc < 2) { fprintf(stderr, "see source\n"); return 1; }
	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	if (!strcmp(argv[1], "stat") && argc == 6) {
		uint64_t a = strtoull(argv[2], 0, 0); unsigned pitch = strtoul(argv[3], 0, 0), w = atoi(argv[4]), h = atoi(argv[5]);
		volatile uint8_t *b = (volatile uint8_t *)map(a, (size_t)pitch * h, &off);
		unsigned first = h, last = 0, minx = w, maxx = 0; unsigned long nz = 0; uint32_t sample = 0;
		for (unsigned y = 0; y < h; y++)
			for (unsigned x = 0; x < w; x++) {
				uint32_t v = *(volatile uint32_t *)(b + (size_t)y * pitch + x * 4);
				if (v) { nz++; if (y < first) first = y; last = y; if (x < minx) minx = x; if (x > maxx) maxx = x; if (!sample) sample = v; }
			}
		printf("nonzero=%lu rows %u..%u cols %u..%u sample=0x%08x\n", nz, first, last, minx, maxx, sample);
	} else if (!strcmp(argv[1], "fill") && argc == 9) {
		uint64_t a = strtoull(argv[2], 0, 0); unsigned pitch = strtoul(argv[3], 0, 0);
		unsigned x0 = atoi(argv[4]), y0 = atoi(argv[5]), w = atoi(argv[6]), h = atoi(argv[7]); uint32_t c = strtoul(argv[8], 0, 0);
		volatile uint8_t *b = (volatile uint8_t *)map(a, (size_t)pitch * (y0 + h), &off);
		for (unsigned y = y0; y < y0 + h; y++)
			for (unsigned x = x0; x < x0 + w; x++) *(volatile uint32_t *)(b + (size_t)y * pitch + x * 4) = c;
		__sync_synchronize(); printf("filled\n");
	} else if (!strcmp(argv[1], "trig")) {
		int n = argc > 2 ? atoi(argv[2]) : 1, ms = argc > 3 ? atoi(argv[3]) : 100;
		volatile uint32_t *d = map(DSI, 0x1000, &off), *m = map(MUTEX, 0x1000, &off);
		for (int i = 0; i < n; i++) {
			d[0x0c / 4] = 0;                      /* DSI_INTSTA: write 0 clears */
			uint32_t seen = 0; double t0 = now(), tdone = 0;
			m[0x20 / 4] = 1;                      /* MUTEX0_EN */
			d[0x00 / 4] = 0; d[0x00 / 4] = 1;     /* DSI_START */
			while (now() - t0 < ms / 1000.0) {
				uint32_t s = d[0x0c / 4]; seen |= s;
				if ((s & 0x10) && !tdone) tdone = now() - t0;
				usleep(200);
			}
			printf("frame %d: INTSTA seen=0x%08x (CMD_DONE=%d TE=%d FRAME_DONE=%d busy=%d) done@%.1fms MUTEX_EN=%u START=%u\n",
			       i, seen, !!(seen & 2), !!(seen & 4), !!(seen & 0x10), !!(seen & 0x80000000), tdone * 1e3,
			       m[0x20 / 4], d[0]);
		}
	} else if (!strcmp(argv[1], "dump") && argc >= 7) {
		uint64_t a = strtoull(argv[2], 0, 0); unsigned pitch = strtoul(argv[3], 0, 0), w = atoi(argv[4]), h = atoi(argv[5]);
		int n = argc > 7 ? atoi(argv[7]) : 1, ms = argc > 8 ? atoi(argv[8]) : 0;
		volatile uint8_t *b = (volatile uint8_t *)map(a, (size_t)pitch * h, &off);
		FILE *o = fopen(argv[6], "wb"); if (!o) { perror(argv[6]); return 1; }
		uint32_t *row = malloc(w * 4);
		for (int k = 0; k < n; k++) {
			for (unsigned y = 0; y < h; y++) {
				for (unsigned x = 0; x < w; x++) row[x] = *(volatile uint32_t *)(b + (size_t)y * pitch + x * 4);
				fwrite(row, 4, w, o);
			}
			if (ms) usleep(ms * 1000);
		}
		fclose(o); printf("dumped %d\n", n);
	} else if (!strcmp(argv[1], "rd") && argc >= 3) {
		uint64_t a = strtoull(argv[2], 0, 0); int n = argc > 3 ? atoi(argv[3]) : 1;
		volatile uint32_t *r = map(a, n * 4, &off);
		for (int i = 0; i < n; i++) printf("0x%llx: 0x%08x\n", (unsigned long long)(a + 4 * i), r[i]);
	} else { fprintf(stderr, "bad args\n"); return 1; }
	return 0;
}
