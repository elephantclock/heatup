#!/usr/bin/awk -f
# Turns a heatup CSV log into a readable thermal/fan report.
# Columns: elapsed,phase,temp_max,temp_die,fan0,fan1
BEGIN { FS = "," }
NR == 1 { next }
{
    i++
    E[i] = $1 + 0; PH[i] = $2; TM[i] = $3 + 0
    TD[i] = $4 + 0; F0[i] = $5 + 0; F1[i] = $6 + 0
}
END {
    if (i < 2) { print "not enough samples"; exit 1 }

    bt = TD[1]; bm = TM[1]; b0 = F0[1]; b1 = F1[1]

    pt = -999; pm = -999; p0 = -1; p1 = -1
    ptAt = 0; p0At = 0; loadEnd = 0; nLoad = 0
    rampAt = -1; halfAt = -1
    for (j = 1; j <= i; j++) {
        if (PH[j] != "load") continue
        nLoad++
        if (TD[j] > pt) { pt = TD[j]; ptAt = E[j] }
        if (TM[j] > pm) pm = TM[j]
        if (F0[j] > p0) { p0 = F0[j]; p0At = E[j] }
        if (F1[j] > p1) p1 = F1[j]
        if (rampAt < 0 && F0[j] > b0 + 200) rampAt = E[j]
        loadEnd = j
    }
    if (rampAt < 0 && p0 > 0 && b0 == 0) {
        for (j = 1; j <= i; j++)
            if (PH[j] == "load" && F0[j] > 0) { rampAt = E[j]; break }
    }
    for (j = 1; j <= i; j++)
        if (PH[j] == "load" && halfAt < 0 && F0[j] >= p0 * 0.5 && p0 > 0) halfAt = E[j]

    printf "\n"
    printf "════════════════ HEATUP REPORT ════════════════\n\n"
    printf "  %-22s %10s %10s %10s\n", "", "BASELINE", "PEAK", "END OF LOAD"
    printf "  %-22s %9.1fC %9.1fC %9.1fC\n", "die temp (CPU/GPU)", bt, pt, TD[loadEnd]
    printf "  %-22s %9.1fC %9.1fC %9.1fC\n", "hottest sensor", bm, pm, TM[loadEnd]
    printf "  %-22s %8.0f %10.0f %10.0f\n", "fan0 (rpm)", b0, p0, F0[loadEnd]
    printf "  %-22s %8.0f %10.0f %10.0f\n", "fan1 (rpm)", b1, p1, F1[loadEnd]

    printf "\n  FAN RESPONSE\n"
    if (rampAt >= 0) printf "    spun up from idle at        %ds\n", rampAt
    else             printf "    never spun up above idle\n"
    if (halfAt >= 0) printf "    reached 50%% of peak at      %ds\n", halfAt
    printf "    peak %.0f rpm at %ds (fan0), %.0f rpm (fan1)\n", p0, p0At, p1

    printf "\n  THERMAL\n"
    printf "    die rose %.1fC over baseline (%.1f -> %.1f)\n", pt - bt, bt, pt
    printf "    peak reached at %ds\n", ptAt
    # Plateau check: spread across the final quarter of the load phase.
    q = int(nLoad * 0.75); lo = 999; hi = -999; c = 0; fqA = -1; fqB = -1
    for (j = 1; j <= i; j++) {
        if (PH[j] != "load") continue
        c++
        if (c >= q) {
            if (TD[j] < lo) lo = TD[j]
            if (TD[j] > hi) hi = TD[j]
            if (fqA < 0) fqA = TD[j]
            fqB = TD[j]
        }
    }
    printf "    last quarter of run varied by %.1fC ", hi - lo
    if (hi - lo < 2.0)      printf "-> steady state reached\n"
    else if (fqB > fqA)     printf "-> still climbing (+%.1fC)\n", fqB - fqA
    else                    printf "-> declining (%.1fC) despite constant load\n", fqB - fqA
    printf "    headroom: %.1fC below the ~100C throttle threshold\n", 100 - pt

    ce = 0
    for (j = 1; j <= i; j++) if (PH[j] == "cool") ce = j
    if (ce) {
        printf "\n  COOLDOWN (%ds after load released)\n", E[ce] - E[loadEnd]
        printf "    die %.1fC -> %.1fC   fan0 %.0f -> %.0f rpm\n",
               TD[loadEnd], TD[ce], F0[loadEnd], F0[ce]
    }

    # Timeline, strided to ~16 rows.
    printf "\n  TIMELINE  (die temp, fan0)\n"
    span = (pt > bt) ? pt - bt : 1
    step = int(i / 16); if (step < 1) step = 1
    for (j = 1; j <= i; j += step) {
        bars = int(20 * (TD[j] - bt) / span); if (bars < 0) bars = 0
        bar = ""
        for (b = 0; b < bars; b++) bar = bar "█"
        printf "    %4ds %-5s %5.1fC %5.0f rpm  %s\n", E[j], PH[j], TD[j], F0[j], bar
    }
    printf "\n"
}
