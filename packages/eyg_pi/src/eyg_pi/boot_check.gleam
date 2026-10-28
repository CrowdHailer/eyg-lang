import argv
import eyg_pi/machine as m
import gleam/io
import gleam/javascript/promise
import gleam/string
import simplifile

const prompt = "\n> "

pub fn main() {
  let arguments = argv.load().arguments
  let offline = arguments == ["offline"]
  let local = arguments == ["local"]
  use machine <- promise.await(m.start(offline))
  let checked =
    {
      use _ <- promise.await(m.wait_for(
        machine.output,
        "type /help for shell commands",
        0,
        3000,
      ))
      use _ <- promise.await(m.wait_for(machine.output, prompt, 0, 3000))
      use math <- promise.await(m.response(machine, "!int_add(1, 2)", prompt))
      assert string.contains(math, "\n3\r\n") as math
      io.println("PASS serial console evaluation")
      let assert Ok(guess) = simplifile.read("examples/guess.eyg")
      let guess = string.replace(guess, "\n", " ")
      use signature <- promise.await(m.response(
        machine,
        "/t (_) -> { " <> guess <> " }",
        prompt,
      ))
      assert string.contains(signature, "Prompt(↑String") as signature
      use _ <- promise.await(m.response(machine, guess, "\nguess 1-100> "))
      use invalid <- promise.await(m.response(
        machine,
        "nope",
        "\nguess 1-100> ",
      ))
      assert string.contains(invalid, "\nnot a number\r\n") as invalid
      use lower <- promise.await(m.response(machine, "41", "\nguess 1-100> "))
      assert string.contains(lower, "\nhigher\r\n") as lower
      use won <- promise.await(m.response(machine, "42", prompt))
      assert string.contains(won, "correct in 2")
        && string.contains(won, "\n2\r\n")
        as won
      io.println("PASS typed guest Prompt loop with invalid and valid input")
      use _ <- promise.await(case offline {
        True -> promise.resolve(Nil)
        False -> {
          let fetch =
            "let reply = perform Fetch({method: GET({}), scheme: HTTPS({}), host: \"eyg.run\", port: None({}), path: \"/\", query: None({}), headers: [], body: !string_to_binary(\"\")}) match reply { Ok(reply) -> { reply.status } Error(_) -> { -1 } }"
          let fetch = case local {
            True ->
              fetch
              |> string.replace("HTTPS({})", "HTTP({})")
              |> string.replace("eyg.run", "10.0.2.2")
              |> string.replace("port: None({})", "port: Some(7207)")
            False -> fetch
          }
          use network <- promise.map(m.response(machine, fetch, prompt))
          assert string.contains(network, case local {
            True -> "\n404\r\n"
            False -> "\n200\r\n"
          })
            as network
          io.println(case local {
            True -> "PASS guest HTTP fixture Fetch"
            False -> "PASS guest HTTPS Fetch"
          })
        }
      })
      use package <- promise.await(m.response(
        machine,
        "@standard.integer.add(40, 2)",
        prompt,
      ))
      assert string.contains(package, "\n42\r\n") as package
      io.println(case offline {
        True -> "PASS offline guest package reuse from SD card"
        False -> "PASS guest hub package"
      })
      use sync <- promise.await(m.response(
        machine,
        "perform WriteFile({path: \"/proc/sysrq-trigger\", contents: !string_to_binary(\"s\")})",
        prompt,
      ))
      assert string.contains(sync, "Ok({})") as sync
      use _ <- promise.map(m.response(machine, "perform Sleep(10000)", prompt))
      io.println("PASS guest filesystem flush before stopping QEMU")
      Nil
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use _ <- promise.map(m.stop(machine))
  let assert Ok(_) = checked
}
