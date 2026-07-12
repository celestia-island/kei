// kei_memtest — memory corruption diagnostic for kei kernel.
// Allocates anonymous memory via mmap and brk, writes known patterns,
// reads them back to detect corruption (dirty pages / CoW bugs).
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int check_count = 0;
static int fail_count = 0;

static void check_pattern(const char *name, uint64_t *p, int count, uint64_t expected) {
    int bad = 0;
    for (int i = 0; i < count; i++) {
        if (p[i] != expected) {
            if (bad < 3) {
                dprintf(2, "CORRUPT %s[%d]=%#lx expected %#lx\n", name, i, p[i], expected);
            }
            bad++;
        }
    }
    check_count++;
    if (bad > 0) {
        dprintf(2, "FAIL %s: %d/%d words corrupted\n", name, bad, count);
        fail_count++;
    } else {
        dprintf(2, "OK %s: %d words clean\n", name, count);
    }
}

int main() {
    dprintf(2, "kei_memtest: starting\n");

    // Test 1: mmap anonymous
    size_t sz = 64 * 1024; // 64KB = 16 pages
    uint64_t *m = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) {
        dprintf(2, "mmap failed\n");
        return 1;
    }
    dprintf(2, "mmap at %p\n", m);

    // Touch all pages to trigger demand paging
    for (int i = 0; i < (int)(sz/8); i++) {
        m[i] = 0xDEADBEEFCAFE000ULL + i;
    }

    // Verify
    int bad = 0;
    for (int i = 0; i < (int)(sz/8); i++) {
        if (m[i] != 0xDEADBEEFCAFE000ULL + i) bad++;
    }
    dprintf(2, "mmap write/read: %d/%d corrupted\n", bad, (int)(sz/8));
    if (bad > 0) fail_count++;
    check_count++;

    // Test 2: fresh mmap (should be zeroed)
    uint64_t *m2 = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m2 != MAP_FAILED) {
        // Touch then verify zero
        int nonzero = 0;
        for (int i = 0; i < (int)(sz/8); i++) {
            if (m2[i] != 0) {
                if (nonzero < 3) dprintf(2, "DIRTY m2[%d]=%#lx\n", i, m2[i]);
                nonzero++;
            }
        }
        dprintf(2, "fresh mmap: %d nonzero words (should be 0)\n", nonzero);
        if (nonzero > 0) fail_count++;
        check_count++;
    }

    // Test 3: brk
    uint64_t brk1 = (uint64_t)sbrk(0);
    uint64_t brk2 = (uint64_t)sbrk(4096);
    uint64_t brk3 = (uint64_t)sbrk(0);
    dprintf(2, "brk: %#lx -> %#lx (after +4096) %#lx\n", brk1, brk2, brk3);

    // Test 4: malloc large
    char *buf = (char *)malloc(1024 * 100); // 100KB
    if (buf) {
        memset(buf, 0xAB, 100*1024);
        int bad4 = 0;
        for (int i = 0; i < 100*1024; i++) {
            if ((uint8_t)buf[i] != 0xAB) bad4++;
        }
        dprintf(2, "malloc 100K: %d/%d bytes corrupted\n", bad4, 100*1024);
        if (bad4 > 0) fail_count++;
        check_count++;
        free(buf);
    }

    dprintf(2, "kei_memtest: %d/%d checks failed\n", fail_count, check_count);

    // Now try drawing to fb (like kei_desktop)
    int fd = open("/dev/fb0", O_RDWR);
    if (fd >= 0) {
        dprintf(2, "fb0 opened, writing test pattern\n");
        // Simple blue + green pattern
        static uint32_t fbuf[640 * 480];
        for (int y = 0; y < 480; y++) {
            for (int x = 0; x < 640; x++) {
                if (y < 50) fbuf[y*640+x] = 0xFFEF6140; // blue header (BGRX)
                else if (y < 250) fbuf[y*640+x] = 0xFF345C28; // dark
                else fbuf[y*640+x] = 0xFF7998C3; // green-ish
            }
        }
        write(fd, fbuf, sizeof(fbuf));
        close(fd);
        dprintf(2, "fb write done\n");
    }

    while(1) sleep(3600);
    return fail_count > 0 ? 1 : 0;
}
