//// Check and record an actual HDMI game loaded by its CID from a local hub.

import eyg/ir/cid
import eyg/ir/tree
import eyg/parser
import eyg_pi/build
import eyg_pi/frame
import eyg_pi/machine as m
import filepath
import glasshouse/sha256
import gleam/float
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/string
import javascript/mutable_reference as cell
import loam/system
import midas/continuation
import multiformats/cid/v1
import plinthx/bun/server
import plinthx/node/timers
import simplifile
import tracing/package_fixture

type Recorder {
  Recorder(
    machine: m.Machine,
    directory: String,
    frames: cell.MutableReference(List(#(Int, String))),
  )
}

pub fn main() {
  let assert Ok(source) = simplifile.read("examples/pong.eyg")
  let assert Ok(parsed) = parser.all_from_string(source)
  let module = tree.clear_annotation(parsed)
  let cid =
    cid.from_tree(module, fn(bytes) { continuation.return(sha256.hash(bytes)) })(
      fn(value) { value },
    )
    |> v1.to_string
  let assert Ok(fixture) = package_fixture.start_with_modules([module])
  io.println("Pong CID: " <> cid)
  let assert Ok(cwd) = simplifile.current_directory()
  let directory = filepath.join(cwd, "build/pong-frames")
  case simplifile.exists(directory, False) {
    Ok(True) -> {
      let assert Ok(_) = simplifile.delete(directory)
      Nil
    }
    _ -> Nil
  }
  let assert Ok(_) = simplifile.create_directory_all(directory)
  let assert Ok(_) = simplifile.create_directory_all("docs")
  use machine <- promise.await(m.start(False))
  let recorder = Recorder(machine, directory, cell.new([]))
  let checked =
    {
      use _ <- promise.await(
        wait_ready(recorder, 1200, fn(image) {
          frame.lit(image, 0, 0, True) > 0 && frame.prompt(image)
        }),
      )
      io.println("PASS HDMI shell ready")
      use _ <- promise.await(type_line(recorder, "!int_multiply(6, 7)\n", 0))
      use _ <- promise.await(wait_ready(recorder, 120, frame.prompt))
      use _ <- promise.await(type_line(
        recorder,
        "let pong = #" <> cid <> "\n",
        0,
      ))
      use _ <- promise.await(wait_ready(recorder, 300, frame.prompt))
      assert fixture.count() == 1
        as "The HDMI shell must fetch the module by CID"
      use loaded <- promise.await(m.response(
        machine,
        "let check = #" <> cid,
        "\n> ",
      ))
      assert !string.contains(loaded, "error:") as loaded
      use signature <- promise.await(m.response(
        machine,
        "/t check.play",
        "\n> ",
      ))
      assert string.contains(signature, "ReadKey")
        && string.contains(signature, "Sleep")
        as signature
      assert fixture.count() == 1 as "Both consoles reuse the persistent module"
      io.println("PASS guest CID load, effect signature and cache reuse")
      use _ <- promise.await(type_line(recorder, "/t pong.play\n", 0))
      use _ <- promise.await(wait_ready(recorder, 120, frame.prompt))
      use _ <- promise.await(hold(recorder, 8))
      use _ <- promise.await(type_line(recorder, "pong.play({})\n", 0))
      use _ <- promise.await(
        wait_ready(recorder, 120, fn(image) {
          let #(ball, paddle) = frame.game(image)
          frame.field(image)
          && case ball, paddle {
            Ok(_), Ok(_) -> True
            _, _ -> False
          }
        }),
      )
      use _ <- promise.await(m.command(machine.monitor, "sendkey up 15"))
      use _ <- promise.await(
        wait_ready(recorder, 20, fn(image) {
          let #(_, paddle) = frame.game(image)
          paddle == Ok(7)
        }),
      )
      use changes <- promise.await(play(recorder, 12, -1, -1, -1, 0))
      assert changes > 3 as "The recorded ball must move across frames"
      use _ <- promise.await(m.type_keys(machine, "q"))
      use _ <- promise.await(wait_ready(recorder, 120, frame.prompt))
      use _ <- promise.await(hold(recorder, 8))
      io.println(
        "PASS moving ball, USB paddle controls and q returns to the shell",
      )
      let assert [#(_, last), ..] = cell.get(recorder.frames)
      use _ <- promise.await(
        build.command(".", "ffmpeg", [
          "-v", "error", "-y", "-i", last, "docs/pong-result.png",
        ]),
      )
      use _ <- promise.map(write_video(recorder))
      io.println("Recorded docs/pong.mp4")
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use _ <- promise.await(m.stop(machine))
  use stopped <- promise.map(server.stop(fixture.server, True))
  let assert Ok(_) = stopped
  let assert Ok(_) = checked
}

fn grab(recorder: Recorder) {
  let path =
    filepath.join(
      recorder.directory,
      int.to_string(list.length(cell.get(recorder.frames))) <> ".ppm",
    )
  use bytes <- promise.await(m.screenshot(recorder.machine, path))
  use now <- promise.map(system.run(system.now()))
  let _ = cell.update(recorder.frames, fn(frames) { [#(now, path), ..frames] })
  frame.decode(bytes)
}

fn wait_ready(recorder, attempts, ready) {
  use image <- promise.await(grab(recorder))
  case ready(image), attempts {
    True, _ -> promise.resolve(Nil)
    False, 0 -> panic as "Timed out waiting for the recorded console"
    False, _ -> {
      use _ <- promise.await(timers.sleep(250))
      wait_ready(recorder, attempts - 1, ready)
    }
  }
}

fn type_line(recorder: Recorder, text, count) {
  case string.pop_grapheme(text) {
    Error(_) -> promise.resolve(Nil)
    Ok(#(char, rest)) -> {
      use _ <- promise.await(m.type_keys(recorder.machine, char))
      use _ <- promise.await(case count % 3 {
        0 -> grab(recorder) |> promise.map(fn(_) { Nil })
        _ -> promise.resolve(Nil)
      })
      type_line(recorder, rest, count + 1)
    }
  }
}

fn hold(recorder, frames) {
  case frames {
    0 -> promise.resolve(Nil)
    _ -> {
      use _ <- promise.await(grab(recorder))
      use _ <- promise.await(timers.sleep(250))
      hold(recorder, frames - 1)
    }
  }
}

fn play(
  recorder: Recorder,
  frames,
  previous_x,
  previous_y,
  previous_top,
  changes,
) {
  case frames {
    0 -> promise.resolve(changes)
    _ -> {
      use image <- promise.await(grab(recorder))
      let #(ball, paddle) = frame.game(image)
      assert !frame.prompt(image) as "The game ended before the quit check"
      let #(_, y) = case ball {
        Ok(ball) -> ball
        _ -> #(previous_x, previous_y)
      }
      let top = case paddle {
        Ok(top) -> top
        _ -> previous_top
      }
      let #(x, key) = case ball, paddle {
        Ok(#(x, y)), Ok(top) if x < previous_x && x < 30 ->
          case y < top + 1, y > top + 2 {
            True, _ -> #(x, "up")
            _, True -> #(x, "down")
            _, _ -> #(x, "")
          }
        Ok(#(x, _)), _ -> #(x, "")
        _, _ -> #(previous_x, "")
      }
      use _ <- promise.await(case key {
        "" -> promise.resolve("")
        _ -> m.command(recorder.machine.monitor, "sendkey " <> key <> " 15")
      })
      use _ <- promise.await(timers.sleep(250))
      play(
        recorder,
        frames - 1,
        x,
        y,
        top,
        changes
          + case #(x, y) == #(previous_x, previous_y) {
          True -> 0
          False -> 1
        },
      )
    }
  }
}

fn write_video(recorder: Recorder) {
  let frames = list.reverse(cell.get(recorder.frames))
  let text = concat(frames)
  let assert Ok(_) = simplifile.write("build/pong-frames.txt", text)
  use _ <- promise.map(
    build.command(".", "ffmpeg", [
      "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i",
      "build/pong-frames.txt", "-vf", "scale=800:480,fps=25,format=yuv420p",
      "-c:v", "libx264", "-crf", "23", "docs/pong.mp4",
    ]),
  )
  let assert Ok(_) = simplifile.delete(recorder.directory)
  Nil
}

fn concat(frames) {
  case frames {
    [] -> ""
    [#(_, path)] ->
      "file " <> quote(path) <> "\nduration 0.1\nfile " <> quote(path) <> "\n"
    [#(now, path), #(next, _) as then, ..rest] ->
      "file "
      <> quote(path)
      <> "\nduration "
      <> float.to_string(int.to_float(int.max(next - now, 10)) /. 1000.0)
      <> "\n"
      <> concat([then, ..rest])
  }
}

fn quote(text) {
  "'" <> string.replace(text, "'", "'\\''") <> "'"
}
