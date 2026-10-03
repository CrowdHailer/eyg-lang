#!/usr/bin/env python3
"""Record a real Erlang remote-shell session, then render its PTY output to MP4."""

import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import time

import imageio_ffmpeg
import pexpect
from PIL import Image, ImageDraw, ImageFont
import pyte


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "video"
COLS, ROWS = 100, 22
WIDTH, HEIGHT, FPS = 1600, 1008, 15
PROMPT = r"\([^)]+\)\d+> "
APP_NODE = "eyg_counters_video"
SHELL_NODE = "eyg_shell_video"
HOST = socket.gethostname().split(".")[0]


class Recording:
    def __init__(self):
        self.started = time.monotonic()
        self.events = []
        self.chapters = []
        self.text = []
        self.erl_prompt = 0
        self.transcript = (OUT / "session.txt").open("w")
        env = dict(os.environ, TERM="xterm-256color", PS1="$ ", PS2="> ")
        self.shell = pexpect.spawn(
            "/bin/bash", ["--noprofile", "--norc", "-i"], cwd=str(ROOT),
            env=env, encoding="utf-8", dimensions=(ROWS, COLS), timeout=90,
        )
        self.shell.delaybeforesend = 0
        self.shell.logfile_read = self

    def write(self, text):
        self.events.append([round(time.monotonic() - self.started, 4), "o", text])
        self.text.append(text)
        self.transcript.write(text)
        self.transcript.flush()

    def flush(self):
        pass

    def pause(self, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                self.shell.read_nonblocking(8192, timeout=min(0.05, end - time.monotonic()))
            except pexpect.TIMEOUT:
                pass

    def chapter(self, title, caption):
        print(title, flush=True)
        self.chapters.append({
            "time": round(time.monotonic() - self.started, 4),
            "title": title, "caption": caption,
        })
        self.pause(1)

    def command(self, command, prompt=PROMPT, hold=1.5):
        for char in command:
            self.shell.send("\r" if char == "\n" else char)
            self.pause(0.023 if char != "\n" else 0.25)
        self.shell.send("\r")
        if prompt == PROMPT:
            # OTP's line editor redraws the current prompt on Enter. Wait for
            # the next numbered prompt, which follows actual evaluation.
            self.erl_prompt += 1
            prompt = rf"\([^)]+\){self.erl_prompt}> "
        self.shell.expect(prompt)
        output = self.shell.before
        if "** exception" in output or "init terminating" in output:
            raise RuntimeError(output)
        self.pause(hold)
        return output

    def save(self):
        header = {
            "version": 2, "width": COLS, "height": ROWS,
            "title": "EYG: automatic package loading from an Erlang remote shell",
            "env": {"TERM": "xterm-256color", "SHELL": "/bin/bash"},
        }
        with (OUT / "erl-counter.cast").open("w") as cast:
            for row in [header, *self.events]:
                cast.write(json.dumps(row) + "\n")
        metadata = {"duration": time.monotonic() - self.started, "chapters": self.chapters}
        (OUT / "chapters.json").write_text(json.dumps(metadata, indent=2) + "\n")
        self.transcript.flush()


def stop_node():
    # Only stop this recorder's specifically named node, leaving the user's nodes alone.
    subprocess.run([
        "erl", "-sname", f"eyg_video_cleanup_{os.getpid()}", "-noshell", "-eval",
        f"rpc:call('{APP_NODE}@{HOST}', init, stop, []), halt().",
    ], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    for _ in range(50):
        names = subprocess.run(["epmd", "-names"], capture_output=True, text=True).stdout
        if f"name {APP_NODE} at port" not in names:
            break
        time.sleep(0.1)


def record():
    subprocess.run(["epmd", "-daemon"], check=True)
    names = subprocess.run(["epmd", "-names"], capture_output=True, text=True, check=True).stdout
    if re.search(rf"name ({APP_NODE}|{SHELL_NODE}) at port", names):
        raise RuntimeError("A video demo node is already running; stop it before recording.")
    session = Recording()
    try:
        session.shell.expect(r"\$ ")
        session.chapter("01 / Start the application", "Build the Erlang application and start a named OTP node.")
        session.command("gleam build", prompt=r"\$ ")
        session.command(
            f"erl -detached -sname {APP_NODE} -pa build/dev/erlang/*/ebin \\\n"
            "  -eval '{ok, _} = application:ensure_all_started(erl_counter).'",
            prompt=r"\$ ", hold=2,
        )
        session.chapter("02 / Shell into the cluster", "A second Erlang node connects to the running application's shell.")
        session.command(f"erl -sname {SHELL_NODE} -remsh {APP_NODE}@$(hostname -s)")
        output = session.command("node().")
        assert APP_NODE in output, output
        session.command("nodes().")
        session.chapter("03 / Write an EYG script", "Use @standard directly. There is no package-install or preload command.")
        session.command(
            'Script = "\n'
            '@standard.list.map([\\"apples\\", \\"pears\\", \\"plums\\"], (name) -> {\n'
            '  let _ = perform StartCounter(name)\n'
            '  perform SetTickRate({name: name, seconds: 1})\n'
            '})\n'
            '", ok.',
            hold=3,
        )
        session.command("{ok, Session} = counters_session:start_link().")
        output = session.command('counters_session:cached(Session, {package, <<"standard">>}).')
        assert "false" in output, output
        session.chapter("04 / Check: load the dependency silently", "check fetches @standard from eyg.run. The session retains the returned cache.")
        output = session.command(
            '{ok, Type} = counters_session:check(Session, Script),\n'
            'io:format("~ts~n", [Type]).', hold=4,
        )
        assert "List(" in output, output
        output = session.command("supervisor:which_children(counters_sup).")
        assert "[]" in output, output
        output = session.command(
            'counters_session:cached(Session, {package, <<"standard">>}).',
            hold=3,
        )
        assert "true" in output, output
        session.chapter("05 / Run: reuse the returned cache", "The checked script now executes its effects and starts three counters.")
        output = session.command(
            '{ok, Value} = counters_session:run(Session, Script),\n'
            'io:format("~ts~n", [eyg@interpreter@simple_debug:inspect(Value)]).', hold=3,
        )
        assert "[Ok({}), Ok({}), Ok({})]" in output, output
        output = session.command("supervisor:which_children(counters_sup).", hold=3)
        assert all(name in output for name in ["apples", "pears", "plums"]), output
        output = session.command('counters_api:get_value(<<"apples">>).')
        assert re.search(r"\{ok,[1-9][0-9]*\}", output), output
        session.chapter("Check loads dependencies. Run executes effects.", "Explicit cache in, updated cache out. All application code is Erlang.")
        session.pause(5)
        session.save()
        print(f"Recorded {len(session.events)} PTY events in {time.monotonic() - session.started:.1f}s.")
    except Exception:
        session.save()
        raise
    finally:
        session.shell.close(force=True)
        session.transcript.close()
        stop_node()


PALETTE = {
    "default": "#dbe4ef", "black": "#111827", "red": "#f87171",
    "green": "#70d6ab", "brown": "#f6c177", "blue": "#82aaff",
    "magenta": "#c4a7e7", "cyan": "#7dd3fc", "white": "#e5e7eb",
    "brightblack": "#94a3b8", "brightred": "#fca5a5", "brightgreen": "#a7f3d0",
    "brightbrown": "#fde68a", "brightblue": "#93c5fd", "brightmagenta": "#ddd6fe",
    "brightcyan": "#a5f3fc", "brightwhite": "#ffffff",
}


def color(value):
    return PALETTE.get(value, "#" + value if len(value) == 6 else PALETTE["default"])


def render():
    rows = [json.loads(line) for line in (OUT / "erl-counter.cast").read_text().splitlines()]
    metadata = json.loads((OUT / "chapters.json").read_text())
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.Stream(screen)
    mono = ImageFont.truetype("DejaVuSansMono.ttf", 23)
    small = ImageFont.truetype("DejaVuSansMono.ttf", 17)
    heading = ImageFont.truetype("DejaVuSansMono.ttf", 32)
    label = ImageFont.truetype("DejaVuSansMono.ttf", 23)
    cell_width = mono.getlength("M")
    duration = metadata["duration"]
    chapters = metadata["chapters"]
    events = rows[1:]
    event_index, chapter_index = 0, 0
    writer = imageio_ffmpeg.write_frames(
        str(OUT / "erl-counter.mp4"), (WIDTH, HEIGHT), fps=FPS,
        codec="libx264", pix_fmt_in="rgb24", pix_fmt_out="yuv420p",
        output_params=["-crf", "19", "-preset", "fast", "-movflags", "+faststart"],
    )
    writer.send(None)
    base = None
    poster_saved = False
    try:
        for frame in range(int(duration * FPS) + 1):
            now = frame / FPS
            changed = base is None
            while event_index < len(events) and events[event_index][0] <= now:
                stream.feed(events[event_index][2])
                event_index += 1
                changed = True
            while chapter_index + 1 < len(chapters) and chapters[chapter_index + 1]["time"] <= now:
                chapter_index += 1
                changed = True
            chapter = chapters[chapter_index]
            if changed:
                base = Image.new("RGB", (WIDTH, HEIGHT), "#0b1020")
                draw = ImageDraw.Draw(base)
                draw.text((48, 32), "EYG from an Erlang shell", font=heading, fill="#f1f5f9")
                draw.text((48, 88), chapter["title"], font=label, fill="#70d6ab")
                draw.text((1200, 47), "REAL TERMINAL SESSION", font=small, fill="#8e9db5")
                draw.rounded_rectangle((40, 140, 1560, 922), 15, fill="#101827", outline="#29364c", width=2)
                draw.text((65, 158), "examples/erl_counter", font=small, fill="#94a3b8")
                draw.line((42, 193, 1558, 193), fill="#29364c", width=1)
                for row in range(ROWS):
                    cells = screen.buffer[row]
                    start = 0
                    while start < COLS:
                        fg = cells[start].fg
                        end = start + 1
                        while end < COLS and cells[end].fg == fg:
                            end += 1
                        text = "".join(cells[col].data for col in range(start, end))
                        draw.text((65 + start * cell_width, 210 + row * 31), text, font=mono, fill=color(fg))
                        start = end
                draw.text((48, 947), chapter["caption"], font=small, fill="#aab8cc")
            image = base.copy()
            draw = ImageDraw.Draw(image)
            if int(now * 2) % 2 == 0 and not screen.cursor.hidden:
                x, y = 65 + min(screen.cursor.x, COLS - 1) * cell_width, 210 + screen.cursor.y * 31
                draw.rectangle((x, y + 26, x + cell_width - 2, y + 28), fill="#70d6ab")
            draw.rectangle((40, 989, 40 + 1520 * now / duration, 993), fill="#70d6ab")
            writer.send(image.tobytes())
            if chapter_index == len(chapters) - 1 and not poster_saved:
                image.save(OUT / "poster.png")
                poster_saved = True
    finally:
        writer.close()
    print(f"Rendered {OUT / 'erl-counter.mp4'} ({duration:.1f}s, {WIDTH}x{HEIGHT}, {FPS}fps).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render-only", action="store_true", help="Render an existing captured session")
    args = parser.parse_args()
    if not args.render_only:
        record()
    render()
