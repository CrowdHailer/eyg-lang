#!/usr/bin/env python3
"""Validate deck numbers and local references without building or benchmarking."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

SLIDE_COUNT = 67
METRICS = ("p50_ms", "p95_ms", "max_ms")
CORE_CASES = ((15, "native-i64"), (16, "tail-trace"),
              (17, "ir-pointer-identity"), (18, "static-builtin-map"))
UTIL_CASES = ((19, "utf16"), (20, "properties"), (21, "mapping"),
              (22, "lengths"), (23, "capture"))
TUI_CASES = (
    "cell_interning", "cell_array_reservation", "frame_allocation_lifetime",
    "unused_annotation_walks", "draft_analysis_cache", "history_value_pretty_cache",
    "immutable_scope_cache", "rendered_type_memoization", "rendered_scope_memoization",
    "omit_unused_scope_effect_projections", "picker_query_casefold_once",
    "ansi_style_change_elision", "buffered_jsonl_output",
)
GIT_CASES = (
    "decoded-object-cache", "lazy-index-load", "binary-index-search", "fanout-bounds",
    "cheap-filters-first", "stop-at-result-limit", "stream-packed-objects",
    "delta-output-preallocation", "incremental-object-hash", "fast-write-compression-kernel",
    "fast-write-compression-end-to-end", "existing-object-write-reuse",
)
REPRODUCTION_INPUTS = {
    "util": ("run.py", "prepare.py", "summarize.py", "driver.zig", "README.md"),
    "core-android": ("prepare_probes.py", "build_probes.py", "run_probes.py",
                     "prepare_lifecycle.py", "trace_depth.zig", "run_trace_depth.py", "README.md"),
    "tui": ("prepare.py", "measure.py", "README.md"),
    "host": ("prepare.py", "run.py", "host_probe.zig", "README.md"),
    "git": ("build_ablations.py", "run_ablations.py", "run_ablations_measured.py",
            "kernel.zig", "README-reproduce.md"),
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings(item)


def keyed(items, key="name"):
    result = {}
    for item in items:
        name = item[key]
        if name in result:
            raise ValueError(f"Duplicate evidence case: {name}")
        result[name] = item
    return result


def reference_pairs(evidence_dir: Path):
    evidence = {}

    def load(name):
        if name not in evidence:
            evidence[name] = read_json(evidence_dir / name)
        return evidence[name]

    refs = {}
    historical = load("historical-and-oracle.json")["historical_bundle"]
    refs[14] = (historical["before"], historical["after"])
    core = keyed(load("core-android.json")["core"])
    for index, name in CORE_CASES:
        refs[index] = (core[name]["before"], core[name]["after"])
    util = keyed(load("util.json")["cases"], "case")
    utility_metrics = ("median_ms_per_workload", "p95_ms_per_workload", "max_ms_per_workload")
    for index, name in UTIL_CASES:
        refs[index] = tuple({target: util[name][side][source]
                            for target, source in zip(METRICS, utility_metrics)}
                            for side in ("before", "after"))
    debug = keyed(load("debug-release.json")["core"])["release-fast-build"]
    refs[24] = (debug["before"], debug["after"])
    tui = load("tui.json")["cases"]
    for index, name in enumerate(TUI_CASES, 25):
        refs[index] = (tui[name]["before"], tui[name]["after"])
    git = keyed(load("git.json")["results"])
    for index, name in enumerate(GIT_CASES, 38):
        refs[index] = (git[name]["before"], git[name]["after"])
    host = load("host.json")["cases"]
    for index, before, after, metric in (
        (50, "cooperative/sync", "cooperative/slice", "blocking_statistics"),
        (51, "cooperative/every-step", "cooperative/slice", "total_statistics"),
        (52, "git/sync", "git/worker", "blocking_statistics"),
        (53, "hub/sync", "hub/worker", "blocking_statistics"),
        (54, "cache/cold", "cache/warm", "statistics"),
        (55, "refresh/always", "refresh/miss", "statistics"),
    ):
        refs[index] = (host[before][metric], host[after][metric])
    resize = load("host.json")["resize"]["variants"]
    refs[56] = (resize["periodic-100ms"]["signal_to_poll_return"],
                resize["self-pipe"]["signal_to_poll_return"])
    lifecycle = keyed(load("core-android.json")["lifecycle"], "workload")
    for index, name in ((57, "active"), (58, "idle")):
        refs[index] = (lifecycle[name]["before"], lifecycle[name]["after"])
    return refs


def validate_numbers(slides, references):
    actual = {index for index, slide in enumerate(slides)
              if slide.get("layout") == "performance"}
    if actual != set(references) or len(actual) != 45:
        raise ValueError("Performance slide indexes differ from the 45 declared comparisons")
    count = 0
    for index, pair in references.items():
        rows = slides[index]["rows"]
        if len(rows) != 4 or rows[0] != ["Metric", "Before", "After"]:
            raise ValueError(f"Slide {index + 1}: unexpected comparison table schema")
        for offset, key in enumerate(METRICS, 1):
            row = rows[offset]
            expected_label = ("Median", "p95", "Max")[offset - 1]
            if len(row) != 3 or not row[0].startswith(expected_label):
                raise ValueError(f"Slide {index + 1}: unexpected metric row {row!r}")
            if row[0].endswith("(µs)"):
                multiplier = 1000
            elif row[0].endswith("(ms)"):
                multiplier = 1
            else:
                raise ValueError(f"Slide {index + 1}: missing explicit time unit")
            for column, stats in enumerate(pair, 1):
                expected = f"{stats[key] * multiplier:.3f}"
                if row[column] != expected:
                    raise ValueError(f"Slide {index + 1}, {row[0]}, {rows[0][column]}: "
                                     f"displayed {row[column]!r}, evidence requires {expected!r}")
                count += 1
    return count


def check_paths(slides, package_root: Path, slides_dir: Path):
    paths = set()
    urls = re.compile(r'https?://[^\s<>"`]+')
    local = re.compile(r'(?<![A-Za-z0-9_/])(?:docs|src|tests|git|http|scripts|android|reports|recordings)/'
                       r'[A-Za-z0-9_./-]+\.(?:json|mjs|zig|py|md|sh|kt|mp4|png|cast)')
    github_prefix = "/CrowdHailer/eyg-lang/blob/"
    for text in strings(slides):
        for match in urls.finditer(text):
            url = urlsplit(match.group().rstrip(".,);"))
            if url.netloc != "github.com" or not url.path.startswith(github_prefix):
                continue
            suffix = unquote(url.path[len(github_prefix):])
            _, _, source = suffix.partition("/")
            # The historical dark/git review lives in the pinned reference branch.
            # Only paths inside this package claim a corresponding local source.
            if source.startswith("packages/zig_runtime/"):
                paths.add(package_root / source[len("packages/zig_runtime/"):])
        for match in local.finditer(urls.sub("", text)):
            paths.add(package_root / match.group())
    paths.update(slides_dir / filename for filename in ("deck.json", "build-slides.mjs", "README.md"))
    for path in sorted(paths):
        if not path.is_file():
            raise ValueError(f"Missing local source or evidence: {path}")
    reproduction = [slides_dir / "benchmarks" / folder / filename
                    for folder, names in REPRODUCTION_INPUTS.items() for filename in names]
    for path in reproduction:
        if not path.is_file():
            raise ValueError(f"Missing reproduction input: {path}")
    return len(paths), len(reproduction)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deck", type=Path, default=Path(__file__).with_name("deck.json"),
                        help="deck JSON source (default: beside this script)")
    parser.add_argument("--evidence-dir", type=Path,
                        help="saved evidence directory (default: deck parent/evidence)")
    parser.add_argument("--package-root", type=Path,
                        help="packages/zig_runtime directory (default: locate from script path)")
    args = parser.parse_args()
    try:
        package_root = args.package_root or next(
            p for p in Path(__file__).resolve().parents
            if (p / "src/interpreter.zig").is_file() and (p / "build.zig").is_file())
        deck = args.deck.resolve()
        slides = read_json(deck)
        if not isinstance(slides, list) or len(slides) != SLIDE_COUNT:
            raise ValueError(f"Expected exactly {SLIDE_COUNT} source slides")
        refs = reference_pairs((args.evidence_dir or deck.parent / "evidence").resolve())
        values = validate_numbers(slides, refs)
        paths, inputs = check_paths(slides, package_root.resolve(), deck.parent)
    except (OSError, ValueError, KeyError, TypeError, StopIteration) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        return 1
    print(f"Validated {SLIDE_COUNT} slides, 45 performance tables "
          f"(44 controlled, 1 historical), {values} displayed values, "
          f"{paths} local references and {inputs} reproduction inputs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
