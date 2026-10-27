#!/bin/bash
# Saturate all CPU cores + the GPU while logging die temperature and fan RPM,
# then print a thermal/fan report.
#   usage: heatup.sh [seconds] [sample_interval] [cooldown_seconds]
SECS=${1:-180}
INTERVAL=${2:-5}
COOL=${3:-60}
DIR="$(cd "$(dirname "$0")" && pwd)"
NCPU=$(sysctl -n hw.ncpu)
LOG="$DIR/run-$(date +%Y%m%d-%H%M%S).csv"

sample() {  # $1 = elapsed, $2 = phase
    local t f
    t=$("$DIR/temps" -q)   # maxAll avgAll maxDie
    f=$("$DIR/fans" -q)    # rpm0 rpm1
    echo "$1,$2,$(echo "$t" | awk '{print $1","$3}'),$(echo "$f" | awk '{print $1","$2}')" >> "$LOG"
}

cleanup() {
    pkill -f "$DIR/cpuburn" 2>/dev/null
    pkill -f "$DIR/gpuburn" 2>/dev/null
}
trap 'echo; echo "interrupted — releasing load"; cleanup; exit 130' INT TERM

echo "heatup: ${NCPU} CPU cores + GPU for ${SECS}s, sampling every ${INTERVAL}s"
echo "log: $LOG"
echo "elapsed,phase,temp_max,temp_die,fan0,fan1" > "$LOG"
sample 0 base

for _ in $(seq 1 "$NCPU"); do "$DIR/cpuburn" "$SECS" & done
"$DIR/gpuburn" "$SECS" > "$DIR/.gpuburn.out" 2>&1 &

START=$(date +%s)
while :; do
    sleep "$INTERVAL"
    EL=$(( $(date +%s) - START ))
    [ "$EL" -ge "$SECS" ] && break
    sample "$EL" load
    printf "\r  %3ds  die %sC  fan %s rpm   " \
        "$EL" "$("$DIR/temps" -q | awk '{print $3}')" "$("$DIR/fans" -q | awk '{print $1}')"
done
sample "$SECS" load
wait
echo; echo "load released — watching cooldown for ${COOL}s"

CSTART=$(date +%s)
while :; do
    sleep "$INTERVAL"
    CEL=$(( $(date +%s) - CSTART ))
    sample $(( SECS + CEL )) cool
    [ "$CEL" -ge "$COOL" ] && break
done

awk -f "$DIR/report.awk" "$LOG"
echo "  csv: $LOG"
