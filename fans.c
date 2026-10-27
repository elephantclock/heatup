// Reads fan RPM from the Apple SMC. Reads are unprivileged (only writes need root).
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <stdlib.h>
#include <unistd.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9

typedef struct { char major, minor, build, reserved[1]; uint16_t release; } vers_t;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } plimit_t;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } keyinfo_t;

typedef struct {
    uint32_t key;
    vers_t vers;
    plimit_t pLimitData;
    keyinfo_t keyInfo;
    char result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData_t;

typedef struct { uint32_t dataSize, dataType; uint8_t bytes[32]; } SMCVal_t;

static io_connect_t conn;

static uint32_t k(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) |
           ((uint32_t)s[2] << 8) | (uint32_t)s[3];
}

static kern_return_t call(SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t osz = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in,
                                    sizeof(SMCKeyData_t), out, &osz);
}

static kern_return_t readKey(const char *key, SMCVal_t *val) {
    SMCKeyData_t in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    memset(val, 0, sizeof *val);

    in.key = k(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t r = call(&in, &out);
    if (r != KERN_SUCCESS) return r;

    val->dataSize = out.keyInfo.dataSize;
    val->dataType = out.keyInfo.dataType;
    in.keyInfo.dataSize = val->dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    r = call(&in, &out);
    if (r != KERN_SUCCESS) return r;
    memcpy(val->bytes, out.bytes, sizeof out.bytes);
    return KERN_SUCCESS;
}

// SMC numeric types: "flt " little-endian float, "fpe2" fixed-point, "ui8 "/"ui16".
static double toDouble(SMCVal_t *v) {
    if (v->dataType == k("flt ") && v->dataSize == 4) {
        float f; memcpy(&f, v->bytes, 4); return f;
    }
    if (v->dataType == k("fpe2") && v->dataSize == 2)
        return ((v->bytes[0] << 6) | (v->bytes[1] >> 2));
    if (v->dataSize == 2) return (v->bytes[0] << 8) | v->bytes[1];
    if (v->dataSize == 1) return v->bytes[0];
    return -1;
}

int main(int argc, char **argv) {
    // -q: bare "rpm0 rpm1" on one line, for scripted sampling.
    int quiet = (argc > 1 && strcmp(argv[1], "-q") == 0);
    double interval = (!quiet && argc > 1) ? atof(argv[1]) : 0;
    int count = (!quiet && argc > 2) ? atoi(argv[2]) : 1;

    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!svc) { fprintf(stderr, "AppleSMC not found\n"); return 1; }
    if (IOServiceOpen(svc, mach_task_self(), 0, &conn) != KERN_SUCCESS) {
        fprintf(stderr, "could not open AppleSMC\n"); return 1;
    }
    IOObjectRelease(svc);

    SMCVal_t v;
    int nfans = 0;
    if (readKey("FNum", &v) == KERN_SUCCESS) nfans = (int)toDouble(&v);
    if (nfans <= 0) { fprintf(stderr, "no fans reported (FNum=%d)\n", nfans); return 2; }

    // Min/max RPM per fan, for context on where in its range each one is sitting.
    double mn[8], mx[8];
    for (int i = 0; i < nfans && i < 8; i++) {
        char key[8];
        snprintf(key, sizeof key, "F%dMn", i);
        mn[i] = readKey(key, &v) == KERN_SUCCESS ? toDouble(&v) : -1;
        snprintf(key, sizeof key, "F%dMx", i);
        mx[i] = readKey(key, &v) == KERN_SUCCESS ? toDouble(&v) : -1;
    }

    if (quiet) {
        for (int i = 0; i < nfans && i < 8; i++) {
            char key[8];
            snprintf(key, sizeof key, "F%dAc", i);
            double rpm = readKey(key, &v) == KERN_SUCCESS ? toDouble(&v) : -1;
            printf("%s%.0f", i ? " " : "", rpm);
        }
        printf("\n");
        IOServiceClose(conn);
        return 0;
    }

    printf("%d fan(s) detected", nfans);
    for (int i = 0; i < nfans && i < 8; i++)
        printf(" | fan%d range %.0f-%.0f rpm", i, mn[i], mx[i]);
    printf("\n");

    for (int s = 0; s < count; s++) {
        time_t now = time(NULL);
        struct tm *tm = localtime(&now);
        printf("%02d:%02d:%02d ", tm->tm_hour, tm->tm_min, tm->tm_sec);
        for (int i = 0; i < nfans && i < 8; i++) {
            char key[8];
            snprintf(key, sizeof key, "F%dAc", i);
            double rpm = readKey(key, &v) == KERN_SUCCESS ? toDouble(&v) : -1;
            double pct = (mx[i] > mn[i]) ? 100.0 * (rpm - mn[i]) / (mx[i] - mn[i]) : -1;
            if (pct < 0) pct = 0;
            if (rpm <= 0) printf(" fan%d   off       ", i);
            else printf(" fan%d %5.0f rpm (%3.0f%%)", i, rpm, pct);
        }
        printf("\n");
        fflush(stdout);
        if (s + 1 < count && interval > 0) usleep((useconds_t)(interval * 1e6));
    }
    IOServiceClose(conn);
    return 0;
}
