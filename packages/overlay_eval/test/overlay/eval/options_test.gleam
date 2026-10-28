import gleam/option.{Some}
import overlay/eval/options

pub fn command_line_options_test() {
  assert Ok(
      options.Options(
        ..options.default_options(),
        contexts: ["a.eyg", "b.eyg"],
        model: "mistral:mistral-medium-latest",
        trials: 5,
        tags: ["notes"],
        replay: Some("cassettes"),
        lenient: True,
      ),
    )
    == options.parse(
      [
        "--context", "a.eyg", "--model", "mistral:mistral-medium-latest",
        "--trials", "5", "--context", "b.eyg", "--tag", "notes", "--replay",
        "cassettes", "--lenient",
      ],
      options.default_options(),
    )
  let assert Ok(options.Options(contexts: ["none"], ..)) =
    options.parse([], options.default_options())
  let assert Error(_) =
    options.parse(["--trials", "0"], options.default_options())
  let assert Error(_) = options.parse(["--unknown"], options.default_options())
}

pub fn invalid_replay_options_fail_test() {
  let assert Error(_) =
    options.parse(["--record", "a", "--replay", "b"], options.default_options())
  let assert Error(_) = options.parse(["--lenient"], options.default_options())
}
