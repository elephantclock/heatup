# heatup

**Warm up a cold Apple Silicon Mac and log its temperatures and fan speeds.**
Built after it cleared a cold-weather fan noise on my M2 Max.

heatup saturates every CPU core (NEON FMA) and the GPU (a runtime-compiled Metal
kernel) while sampling die temperature and fan RPM, then prints a report. No sudo,
nothing to install beyond Apple's command-line tools.

## The story

My MacBook Pro (M2 Max) started making a crackling, buzzing noise when it had been
sitting in a cold, damp room. Apple support couldn't reproduce it. Running a few
minutes of full load, which warms the whole machine and spins the fans up to
~3,500 rpm, made the noise go away every time.

I don't know exactly why. My best guesses are fan bearings that get stiff when cold,
or light condensation that evaporates once the machine is warm. This is one machine's
experience, not a tested fix.

> [!WARNING]
> **This is not a fix for liquid damage.** If liquid got into your Mac, shut it down,
> unplug it, and get it inspected. Do **not** run this. Putting full power through a
> wet logic board is how shorts and corrosion happen.
>
> If your Mac has just come in from the cold, let it sit at room temperature for
> 30–60 minutes before running anything.

## Compatibility

| Mac | Status |
|---|---|
| M2 Max MacBook Pro | ✅ Built and tested here |
| Other M1–M4 MacBook Pro, Mac mini, Mac Studio, iMac | ⚠️ Should work, untested. Check `./temps` output first (see [Caveats](#caveats)) |
| MacBook Air (any) | ⚠️ Load and temperatures work; no fans, so fan columns stay empty |
| Intel Macs | ❌ Not supported (`cpuburn` uses ARM NEON; sensors are read differently) |

If you run it on another model, please open an issue with your `./temps` output and a
report. That's the fastest way to make it work everywhere.

## Build

```sh
git clone https://github.com/elephantclock/heatup.git
cd heatup
clang -O3 -march=native cpuburn.c -o cpuburn
swiftc -O gpuburn.swift -o gpuburn
swiftc -O temps.swift -o temps -framework IOKit -framework CoreFoundation
clang -O2 fans.c -o fans -framework IOKit
```

Build on the Mac you'll run it on. `-march=native` ties `cpuburn` to the host CPU.

## Usage

```sh
./heatup.sh [seconds] [sample_interval] [cooldown_seconds]
```

Defaults: `180 5 60`.

**The first argument is seconds, not minutes.** `./heatup.sh 5` burns for five
seconds. Five minutes is `./heatup.sh 300`.

```sh
./heatup.sh 300 5 30     # 5 min load, sample every 5s, 30s cooldown
```

Ctrl-C (or `TERM`) hits a trap that kills both burners and exits 130, so an
interrupted run never leaves load behind.

### Don't stack runs

A second run started while one is in flight puts twice as many burners on the same
cores. That halves each process's throughput instead of heating the machine any
harder, and both runs' logs become meaningless. Check first:

```sh
pgrep -f "$PWD/(cpu|gpu)burn" | wc -l     # expect 0 when idle
```

If you script a wait-for-previous, **gate on `heatup.sh`, not on `cpuburn`.** The
burners exit before the script's cooldown loop finishes, so a `cpuburn` gate opens
early and the new run's heat lands in the old run's cooldown rows.

## Output

Each run writes `run-YYYYmmdd-HHMMSS.csv` next to the script:

```
elapsed,phase,temp_max,temp_die,fan0,fan1
```

`phase` is `base` (one row, pre-load), `load`, or `cool`. `temp_die` is the max
across CPU/GPU die sensors; `temp_max` is the max across all sensors, which includes
a PMU calibration reference that reads high, so prefer `temp_die`.

The report is decoupled from the run on purpose. Regenerate one from any CSV without
re-burning:

```sh
awk -f report.awk examples/run-300s-m2max.csv
```

`.gpuburn.out` holds the GPU's dispatch count for the most recent run. Dispatches ÷
seconds is a useful GPU-throttling proxy across runs (41.0 / 41.3 / 40.8 per second
on the M2 Max, ~1% spread).

## Individual tools

| | |
|---|---|
| `./temps` | all sensors, sorted, with max/avg/die-max summary |
| `./temps -q` | `maxAll avgAll maxDie` on one line |
| `./fans [interval] [count]` | RPM with each fan's % of its range |
| `./fans -q` | `rpm0 rpm1` on one line |
| `./cpuburn <seconds>` | one core; the script launches `hw.ncpu` of them |
| `./gpuburn <seconds>` | GPU only |

`-q` is the scripted-sampling form `heatup.sh` uses.

## Reference numbers (M2 Max, 12 CPU / 38 GPU cores)

From 13 full runs, consistent to within ~1.3 °C and ~60 rpm. Two sample logs are in
[`examples/`](examples/). Use these to sanity-check the same model. Other chips will
differ, so record your own baseline when the machine is healthy.

| | |
|---|---|
| Baseline die | 35–45 °C |
| Peak die under full load (300 s) | 67–69 °C |
| fan0 / fan1 peak | ~3,490 / ~3,800 rpm |
| Fans spin up from idle at | 21–37 s (later from a colder start) |

No thermal throttling was observed. Short 180 s runs from a cold start (30–38 °C
baseline) can finish a few degrees below these peaks because they never reach
steady state.

## Caveats

- **Sensor names differ across chip generations.** The die filter in `temps.swift`
  matches names containing `tdie` or `TP`. If nothing matches, `temp_die` falls back
  to the hottest sensor overall, which can be a calibration reference rather than the
  chip. Check `./temps` output on a new machine before trusting `temp_die`.
- **Missing readings are not errors.** If `temps` or `fans` fails, `heatup.sh` writes
  empty fields and the report treats them as 0.
- **The ~100 °C headroom line in the report is an assumed reference,** not a measured
  property of any machine. M3/M4 Max chips are reported to run much closer to it under
  full load, and that is normal for them.
- **Unexplained late-run cooling.** In 2 of 3 monitored 300 s runs, die temp *fell*
  3–6 °C during the final stretch under constant load and constant fan speed
  (see `examples/run-300s-m2max.csv`). Settling it would need clock residencies from
  `sudo powermetrics`.
- Temperatures come from IOHIDEventSystem and fan speeds from AppleSMC, both private
  interfaces. A future macOS update could break them. Reads only; nothing here writes
  to the SMC.

## License

MIT
