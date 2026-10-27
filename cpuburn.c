// Vector FMA burner: keeps all NEON pipes fed for maximum package power.
#include <arm_neon.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char **argv) {
    double seconds = argc > 1 ? atof(argv[1]) : 180.0;
    struct timespec t0, now;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    float32x4_t a[8], b, c;
    b = vdupq_n_f32(1.0000001f);
    c = vdupq_n_f32(0.9999999f);
    for (int i = 0; i < 8; i++) a[i] = vdupq_n_f32(1.0f + i * 0.01f);

    for (;;) {
        for (long k = 0; k < 2000000; k++) {
            for (int i = 0; i < 8; i++) a[i] = vfmaq_f32(c, a[i], b);
            for (int i = 0; i < 8; i++) a[i] = vmulq_n_f32(a[i], 0.9f);
        }
        clock_gettime(CLOCK_MONOTONIC, &now);
        double el = (now.tv_sec - t0.tv_sec) + (now.tv_nsec - t0.tv_nsec) / 1e9;
        if (el >= seconds) break;
    }

    float sink = 0;
    for (int i = 0; i < 8; i++) sink += vgetq_lane_f32(a[i], 0);
    if (sink == 12345.678f) printf("%f\n", sink);
    return 0;
}
