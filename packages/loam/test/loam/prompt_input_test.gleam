import gleam/bit_array
import gleam/javascript/promise
import gleam/string
import plinthx/bun/runtime
import plinthx/bun/subprocess
import plinthx/node/process

pub fn prompts_preserve_later_stdin_bytes_test() {
  check(
    "remaining",
    bit_array.from_string("one🌱\r\ntwo\nremaining🌱"),
    "PASS prompts leave remaining stdin bytes intact",
  )
}

pub fn final_unterminated_line_and_eof_test() {
  check(
    "eof",
    bit_array.from_string("one🌱\ntwo\nlast🌱"),
    "PASS partial final line and EOF",
  )
}

pub fn invalid_utf8_is_an_error_instead_of_an_empty_line_test() {
  check("invalid", <<255, 10>>, "PASS invalid UTF-8 returns an input error")
}

fn check(mode, input, expected) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let assert Ok(child) =
    subprocess.spawn_with_input(
      bun,
      subprocess.Options(
        ["gleam", "run", "--runtime", "bun", "-m", "support/prompt_process"],
        ".",
        [#("EYG_PROMPT_CHECK", mode), ..process.env(host)],
        "pipe",
        "pipe",
        "pipe",
      ),
      input,
    )
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(stderr) = subprocess.stderr(child)
  use output <- promise.await(subprocess.readable_stream_to_text(bun, stdout))
  use errors <- promise.await(subprocess.readable_stream_to_text(bun, stderr))
  use status <- promise.map(subprocess.exited(child))
  let assert Ok(errors) = errors
  let assert Ok(0) = status as errors
  let assert Ok(output) = output
  assert string.contains(output, expected) as output
}
