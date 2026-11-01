// Reads mockwow.lua's output on stdin, decodes the strip frames with the shim's decoder and checks
// the rects against the expected ones. Exit 0 if the message decodes and matches.
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "../../shims/appkit/sphoverstrip.h"

int main(void) {
    int want_n;
    if (scanf("expect %d\n", &want_n) != 1) return 2;
    sph_rect *want = calloc(want_n, sizeof *want);
    for (int i = 0; i < want_n; i++)
        if (scanf("%f %f %f %f\n", &want[i].x, &want[i].y, &want[i].w, &want[i].h) != 4) return 2;
    static sph_assembler a;
    sph_reset(&a);
    static sph_rect got[SPH_MAX_RECTS];
    int got_n = -1, frames = 0, valid = 0;
    char line[SPH_BLOCKS + 8];
    while (fgets(line, sizeof line, stdin)) {
        uint8_t rgb[SPH_BLOCKS], frame[SPH_FRAME_BYTES];
        for (int i = 0; i < SPH_BLOCKS; i++) rgb[i] = line[i] - '0';
        frames++;
        if (!sph_frame_from_blocks(rgb, frame)) continue;
        valid++;
        int n;
        if (sph_feed(&a, frame, got, &n) == SPH_MESSAGE) {
            got_n = n;
            printf("message after %d frames: %d rects in %d chunks\n", frames, n, a.count);
        }
    }
    printf("%d frames, %d valid\n", frames, valid);
    if (got_n != want_n) {
        printf("FAIL: %d rects, expected %d\n", got_n, want_n);
        return 1;
    }
    int bad = 0;
    for (int i = 0; i < want_n; i++) {
        // 12-bit fractions: within 1/4095 of the screen, plus rounding of both corners.
        float tol = 1.5f / 4095;
        if (fabsf(got[i].x - want[i].x) > tol || fabsf(got[i].y - want[i].y) > tol ||
            fabsf(got[i].w - want[i].w) > 2 * tol || fabsf(got[i].h - want[i].h) > 2 * tol) {
            printf("FAIL rect %d: got %f %f %f %f, expected %f %f %f %f\n", i, got[i].x, got[i].y, got[i].w,
                   got[i].h, want[i].x, want[i].y, want[i].w, want[i].h);
            bad++;
        }
    }
    if (bad) return 1;
    printf("ok: %d rects match\n", want_n);
    return 0;
}
