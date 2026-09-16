#!/usr/bin/env python3
"""Retiming for the recorded demo, using its actual Ollama streaming timestamps.

FFMPEG=/path/to/ffmpeg python3 demo/speed-up-thinking.py [--plan-only]

The original recording is preserved. Only intervals where the model's thinking
indicator is active are accelerated: from its first thinking chunk until the
first visible answer/tool call. This includes tool-call generation while the
UI is still showing thinking, but leaves tool execution and interactions alone.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess


def timestamp(value):
    value = re.sub(r"(\.\d{6})\d+", r"\1", value)
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def probe(ffmpeg, video):
    result = subprocess.run(
        [ffmpeg, "-hide_banner", "-i", str(video)], capture_output=True, text=True
    )
    text = result.stderr
    duration = re.search(r"Duration: (\d+):(\d+):(\d+\.\d+)", text)
    if not duration:
        raise RuntimeError(text)
    hours, minutes, seconds = map(float, duration.groups())
    creation = re.search(r"creation_time\s*:\s*(\S+)", text)
    return {
        "duration": hours * 3600 + minutes * 60 + seconds,
        "created": timestamp(creation[1]) if creation else None,
        "audio": "Audio:" in text,
    }


def thinking_intervals(transcript, origin, duration):
    intervals = []
    for response in transcript:
        chunks = [c for c in response.get("chunks", []) if c.get("created_at")]
        if not chunks:
            continue
        # Map the provider's clock to the browser's clock using the recorded
        # response completion. Network/render timing is only known to this
        # granularity in the original recording.
        clock_offset = timestamp(response["at"]) - timestamp(chunks[-1]["created_at"])
        start = None
        for chunk in chunks:
            time = timestamp(chunk["created_at"]) + clock_offset - origin
            time = max(0, min(duration, time))
            message = chunk.get("message", {})
            if message.get("thinking") and start is None:
                start = time
            if start is not None and (message.get("content") or message.get("tool_calls")):
                if time > start:
                    intervals.append((start, time))
                start = None
        if start is not None:
            end = min(duration, timestamp(response["at"]) - origin)
            if end > start:
                intervals.append((start, end))
    merged = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    return merged


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path("recordings"))
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    ffmpeg = os.environ.get("FFMPEG", "ffmpeg")
    source = args.directory / "artifacts-demo.webm"
    output = args.directory / "artifacts-demo-thinking-10x.mp4"
    info = probe(ffmpeg, source)
    if info["audio"]:
        raise RuntimeError("This editor expects the original silent screencast")
    if info["created"] is None:
        raise RuntimeError("Recording has no creation_time for transcript alignment")
    transcript = json.loads((args.directory / "agent-transcript.json").read_text())["transcript"]
    intervals = thinking_intervals(transcript, info["created"], info["duration"])
    if not intervals:
        raise RuntimeError("No timestamped thinking intervals were found")
    speed = 10
    saving = 1 - 1 / speed
    accelerated = sum(end - start for start, end in intervals)

    def retime(time):
        return time - saving * sum(max(0, min(time, end) - start) for start, end in intervals)

    plan = {
        "source": source.name,
        "output": output.name,
        "thinking_speed": speed,
        "other_speed": 1,
        "source_duration": info["duration"],
        "expected_output_duration": retime(info["duration"]),
        "thinking_seconds": accelerated,
        "intervals": [
            {"source_start": a, "source_end": b, "output_start": retime(a), "output_end": retime(b)}
            for a, b in intervals
        ],
        "prompts": [
            {"source_time": timestamp(r["at"]) - info["created"],
             "output_time": retime(timestamp(r["at"]) - info["created"]),
             "prompt": r["prompt"]}
            for r in transcript if "prompt" in r
        ],
    }
    (args.directory / "thinking-10x-timeline.json").write_text(json.dumps(plan, indent=2) + "\n")
    print(f"{len(intervals)} thinking intervals, {accelerated:.2f}s of source footage")
    print(f"Duration: {info['duration']:.2f}s → {plan['expected_output_duration']:.2f}s")
    for a, b in intervals:
        print(f"  {a:8.3f}–{b:8.3f}s → {retime(a):8.3f}–{retime(b):8.3f}s (10×)")
    if args.plan_only:
        return
    # A continuous piecewise-linear time mapping avoids cutting/rejoining GOPs
    # or loading dozens of full-video branches into a concat filter. Normal
    # sections retain their original duration. fps discards compressed frames.
    terms = "+".join(f"min(max(T-{a:.6f},0),{b-a:.6f})" for a, b in intervals)
    filters = f"setpts='(PTS-STARTPTS)-{saving}*({terms})/TB',fps=25"
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "warning", "-nostats", "-y",
        "-i", str(source), "-an", "-vf", filters,
        "-c:v", "libx264", "-crf", "18", "-preset", "veryfast",
        "-threads", "4", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        "-map_metadata", "-1",
        "-metadata", "title=Overlay artifacts — thinking at 10x",
        str(output),
    ], check=True)
    edited = probe(ffmpeg, output)
    if abs(edited["duration"] - plan["expected_output_duration"]) > 0.12:
        raise RuntimeError(f"Unexpected edited duration: {edited['duration']}")
    subprocess.run([ffmpeg, "-v", "error", "-i", str(output), "-f", "null", "-"], check=True)
    print(f"Verified {output}: {edited['duration']:.2f}s; original preserved")


if __name__ == "__main__":
    main()
