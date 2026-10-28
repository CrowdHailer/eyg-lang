//// QEMU lifecycle and monitor protocol, with serial output retained by Gleam.

import eyg_pi/emulate
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import javascript/mutable_reference as cell
import plinthx/browser/readable_stream as stream
import plinthx/bun/runtime
import plinthx/bun/subprocess
import plinthx/node/net
import plinthx/node/process
import plinthx/node/timers
import simplifile

pub type Monitor {
  Monitor(socket: net.Socket, output: cell.MutableReference(String))
}

pub type Machine {
  Machine(
    child: subprocess.Subprocess,
    monitor: Monitor,
    output: cell.MutableReference(String),
  )
}

pub fn start(offline) {
  let path = "build/monitor.sock"
  case simplifile.exists(path, False) {
    Ok(True) -> {
      let assert Ok(_) = simplifile.delete(path)
      Nil
    }
    _ -> Nil
  }
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let cmd =
    list.append(emulate.arguments(offline, True, "stdio"), [
      "-monitor",
      "unix:" <> path <> ",server=on,wait=off",
    ])
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(cmd, ".", process.env(host), "pipe", "pipe", "inherit"),
    )
  let output = cell.new("")
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(reader) = stream.get_text_reader(stdout)
  let _ = pump(reader, output)
  use connected <- promise.await(connect(path, 100))
  use socket <- promise.await(case connected {
    Ok(socket) -> promise.resolve(socket)
    Error(reason) -> {
      let _ = subprocess.kill(child, "SIGTERM")
      use _ <- promise.map(subprocess.exited(child))
      panic as reason
    }
  })
  let monitor_output = cell.new("")
  net.on_data(socket, fn(text) {
    let _ = cell.update(monitor_output, fn(old) { old <> text })
    Nil
  })
  net.on_error(socket, io.print_error)
  let monitor = Monitor(socket, monitor_output)
  let machine = Machine(child, monitor, output)
  use ready <- promise.await(
    wait_for(monitor_output, "(qemu) ", 0, 100)
    |> promise.map(Ok)
    |> promise.rescue(Error),
  )
  use _ <- promise.map(case ready {
    Ok(_) -> promise.resolve(Nil)
    Error(_) -> stop(machine)
  })
  let assert Ok(_) = ready
  machine
}

fn connect(path, attempts) {
  use socket <- promise.await(net.connect_unix(path))
  case socket, attempts {
    Ok(socket), _ -> promise.resolve(Ok(socket))
    Error(reason), 0 -> promise.resolve(Error(reason))
    Error(_), _ -> {
      use _ <- promise.await(timers.sleep(100))
      connect(path, attempts - 1)
    }
  }
}

fn pump(reader, output) {
  use chunk <- promise.await(stream.read_text(reader))
  let assert Ok(chunk) = chunk
  case chunk {
    None -> promise.resolve(Nil)
    Some(text) -> {
      let _ = cell.update(output, fn(old) { old <> text })
      pump(reader, output)
    }
  }
}

pub fn wait_for(output, text, since, attempts) {
  let current = cell.get(output)
  let tail = string.slice(current, since, string.length(current))
  case string.contains(tail, text), attempts {
    True, _ -> promise.resolve(tail)
    False, 0 -> {
      let message = "Timed out waiting for " <> text <> " in " <> tail
      panic as message
    }
    False, _ -> {
      use _ <- promise.await(timers.sleep(100))
      wait_for(output, text, since, attempts - 1)
    }
  }
}

pub fn serial(machine: Machine, text) {
  let mark = string.length(cell.get(machine.output))
  let assert Ok(_) = subprocess.write_input(machine.child, text <> "\r")
  mark
}

pub fn response(machine: Machine, text, until) {
  let mark = serial(machine, text)
  wait_for(machine.output, until, mark, 1800)
}

pub fn command(monitor: Monitor, text) {
  let mark = string.length(cell.get(monitor.output))
  let assert Ok(_) = net.write(monitor.socket, text <> "\n")
  wait_for(monitor.output, "(qemu) ", mark, 100)
}

pub fn stop(machine: Machine) {
  net.close(machine.monitor.socket)
  let _ = subprocess.kill(machine.child, "SIGTERM")
  use _ <- promise.map(subprocess.exited(machine.child))
  Nil
}

pub fn screenshot(machine: Machine, path: String) {
  use result <- promise.map(command(machine.monitor, "screendump " <> path))
  assert !string.contains(result, "Error") as result
  let assert Ok(bytes) = simplifile.read_bits(path)
  bytes
}

pub fn wait_screen(machine: Machine, path, ready, attempts) {
  use bytes <- promise.await(screenshot(machine, path))
  case ready(bytes), attempts {
    True, _ -> promise.resolve(bytes)
    False, 0 -> panic as "HDMI console did not become ready"
    False, _ -> {
      use _ <- promise.await(timers.sleep(500))
      wait_screen(machine, path, ready, attempts - 1)
    }
  }
}

pub fn type_keys(machine: Machine, text) {
  type_chars(machine, string.to_graphemes(text))
}

fn type_chars(machine: Machine, chars: List(String)) {
  case chars {
    [] -> promise.resolve(Nil)
    [char, ..rest] -> {
      let key = case char {
        " " -> "spc"
        "(" -> "shift-9"
        ")" -> "shift-0"
        "," -> "comma"
        "!" -> "shift-1"
        "_" -> "shift-minus"
        "\n" -> "ret"
        "\"" -> "shift-apostrophe"
        "/" -> "slash"
        "." -> "dot"
        "@" -> "shift-2"
        "{" -> "shift-bracket_left"
        "}" -> "shift-bracket_right"
        ":" -> "shift-semicolon"
        "-" -> "minus"
        ">" -> "shift-dot"
        "=" -> "equal"
        "#" -> "shift-3"
        char ->
          case
            string.uppercase(char) == char && string.lowercase(char) != char
          {
            True -> "shift-" <> string.lowercase(char)
            False -> char
          }
      }
      use _ <- promise.await(command(
        machine.monitor,
        "sendkey " <> key <> " 15",
      ))
      type_chars(machine, rest)
    }
  }
}
