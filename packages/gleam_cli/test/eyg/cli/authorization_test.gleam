import eyg/analysis/inference/levels_j/contextual as infer
import eyg/cli/check
import eyg/cli/helpers
import eyg/cli/overlay
import eyg/interpreter/value
import gleam/http/response
import gleam/list
import gleam/option.{Some}
import gleam/string
import loam/execute
import loam/sandbox
import loam/sandbox/fs
import loam/source
import simplifile

fn state() {
  helpers.state()
}

fn files() {
  let root = "../../eyg_packages/authorization"
  let assert Ok(names) = simplifile.read_directory(root)
  list.fold(names, sandbox.sandbox(), fn(env, name) {
    let assert Ok(code) = simplifile.read(root <> "/" <> name)
    sandbox.with_file(env, "/eyg_packages/authorization/" <> name, code)
  })
}

fn evaluate(code, input, env) {
  let assert Ok(source) = source.parse_input(code, input)
  let assert #(sandbox.Returned(#(Ok(#(Some(value), _)), _)), env) =
    execute.block(source, [], state()) |> sandbox.run(env)
  #(value, env)
}

pub fn every_authorization_tutorial_example_executes_test() {
  let assert Ok(document) = simplifile.read("../../guides/authorization.md")
  let assert [_, ..blocks] = string.split(document, "```eyg\n")
  assert list.length(blocks) == 9
  list.each(blocks, fn(block) {
    let assert Ok(#(code, _)) = string.split_once(block, "```")
    let assert Ok(parsed) =
      source.parse_input(code, source.File("/guides/authorization.md"))
    let assert #(sandbox.Returned(#(_, _, errors, _)), _) =
      check.check_from(
        parsed,
        "/",
        infer.pure(),
        state(),
        check.allway_pass_gate,
      )
      |> sandbox.run(files())
    assert errors == []
    let #(result, _) =
      evaluate(code, source.File("/guides/authorization.md"), files())
    assert result == value.Tagged("True", value.unit())
  })
}

pub fn example_config_conforms_to_the_cli_policy_type_test() {
  let path = "/examples/authorization/overlay.eyg"
  let assert Ok(code) = simplifile.read("../.." <> path)
  let env =
    files()
    |> sandbox.with_env("HOME", "/home/alice")
    |> sandbox.with_file(path, code)
  let assert #(sandbox.Returned(Ok(_)), _) =
    overlay.initialize(source.File(path), helpers.config) |> sandbox.run(env)
  let assert #(
    sandbox.Returned(Error("the configuration exited with status 1")),
    missing_home,
  ) =
    overlay.initialize(source.File(path), helpers.config)
    |> sandbox.run(files() |> sandbox.with_file(path, code))
  assert missing_home.stderr == ["HOME is required\n"]
}

fn test_policy() {
  let code =
    "let {make} = import \"/eyg_packages/authorization/overlay.eyg\"
     let policy = make(@{
       fact Home({tenant: \"acme\", actor: \"alice\", path: \"/home/alice\"}),
       fact AllowedOrigin({tenant: \"acme\", actor: \"alice\", scheme: HTTPS({}), host: \"api.example.com\", port: None({})})
     }, {tenant: \"acme\", actor: \"alice\"})"
  let code = code <> "
    {llm: {provider: Mistral({api_key: \"test\"}), model: \"test\"}, policy, context: {}}
  "
  let assert #(sandbox.Returned(Ok(#(session, _))), _) =
    overlay.initialize(source.Code(code), helpers.config)
    |> sandbox.run(files())
  session
}

pub fn denied_writes_do_not_reach_the_filesystem_test() {
  let env =
    sandbox.sandbox()
    |> sandbox.with_directory("/home/alice")
    |> sandbox.with_file("/private/secret", "unchanged")
  let code =
    "let allowed = perform WriteFile({path: \"/home/alice/./report\", contents: !string_to_binary(\"report\")})
     let denied = perform WriteFile({path: \"/home/alice/../../private/secret\", contents: !string_to_binary(\"bad\")})
     {allowed, denied}"
  let assert #(sandbox.Returned(#(Ok(_), _, _)), env) =
    overlay.check_and_execute(test_policy(), code, state())
    |> sandbox.run(env)
  assert fs.read(env.file_system, "/home/alice/report") == Ok("report")
  assert fs.read(env.file_system, "/private/secret") == Ok("unchanged")
}

pub fn only_permitted_get_requests_reach_the_network_test() {
  let env =
    sandbox.sandbox()
    |> sandbox.with_network(
      fn(_, count) {
        #(Ok(response.Response(200, [], <<"ok":utf8>>)), count + 1)
      },
      0,
    )
  let code =
    "let request = {method: GET({}), scheme: HTTPS({}), host: \"api.example.com\", port: None({}), path: \"/\", query: None({}), headers: [], body: !string_to_binary(\"\")}
     let allowed = perform Fetch(request)
     let post = perform Fetch({method: POST({}), ..request})
     let other = perform Fetch({host: \"evil.example\", ..request})
     {allowed, post, other}"
  let assert #(sandbox.Returned(#(Ok(_), _, _)), env) =
    overlay.check_and_execute(test_policy(), code, state())
    |> sandbox.run(env)
  assert env.network_state == 1
}
