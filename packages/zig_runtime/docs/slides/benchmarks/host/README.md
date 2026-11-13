# Controlled host optimisation probes

These probes compare mechanisms using actual native VM, Git worker and hub APIs.
They do not measure a physical terminal, Android UI, network service in production,
or the final production executable. Synthetic IO delay is deliberately explicit.
The canonical package is never edited.

```sh
python3 prepare.py --repo /path/to/eyg-lang
zig build-exe -OReleaseFast host_probe.zig --global-cache-dir .global-cache --cache-dir .zig-cache -femit-bin=host-probe
python3 run.py --output results.json
```

Preparation copies the canonical sources and records SHA-256 for every input.
Only two scratch controls are added: a configurable VM clock-check mask (default
127 exactly matches production's every 128-step condition), and a 20 ms delay before
Git work. Both Git variants inject the same delay before the same real query.

The cooperative probe executes the same finite recursive sum in an unsliced VM,
a 1 ms-sliced VM checking every step, and a 1 ms-sliced VM checking every 128 steps.
It records every caller blocking interval, total time, yield count and VM steps.
A shorter blocking interval is responsiveness, not faster total evaluation.

The async Git and hub probes compare the synchronous host call with worker-start
acknowledgment, and report actual completion separately. Git performs the actual
20-commit query at the pinned real-world revision. Hub fetches a verified content
module from a local HTTP server with a 20 ms response delay. Replies are verified.

Hub-cache controls clear the module source/value map on every timed lookup;
the warm version reuses it. Both evaluate the same pure recursive sum module.
The custom transport has a 2 ms GET delay. Request counts show avoided work.
Refresh controls force an unnecessary ledger refresh before each known-name
lookup versus the production cache-hit path. A new release then validates an
incremental cursor 5→6 refresh, two GET requests, and zero repeated-known GETs.

The resize comparison is an OS mechanism probe in Python, not the Zig TUI:
actual SIGWINCH after 5 ms, select with 100 ms periodic timeout versus a self-pipe.
All raw times and request counts are retained. No timing sample is filtered.
