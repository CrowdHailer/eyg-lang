import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/http/request
import gleam/http/response
import gleam/option.{Some}
import loam/ir
import loam/platform/computer
import loam/sandbox
import loam/sandbox/fs
import loam/source
import loam/system
import simplifile
import touch_grass/cryptography/create_key
import touch_grass/cryptography/hash
import touch_grass/file_system/append_file
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/harness/computer as harness

const origin = source.Disk("/project/entry.eyg")

pub fn make_directory_is_source_relative_and_deferred_test() {
  let assert system.Cwd(resume) = computer.make_directory(source.Inline, "data")
  let assert system.CreateDirectory("/project/data", resume) =
    resume(Ok("/project"))
  assert resume(Ok(Nil)) == system.Done(Ok(Nil))
  let assert system.CreateDirectory("/project/data", _) =
    computer.make_directory(source.Disk("/project/entry.eyg"), "data")
  let assert system.GenerateKey(_) = computer.create_key(create_key.Eddsa)
}

pub fn construction_defers_source_resolution_and_binary_io_test() {
  let effect = computer.read_file(source.Inline, read_file.Input("data", 2, 3))
  let assert system.Cwd(resume) = effect
  let assert system.ReadFileRange("/project/data", 2, 3, resume) =
    resume(Ok("/project"))
  assert resume(Ok(<<255, 0, 1>>)) == system.Done(Ok(<<255, 0, 1>>))

  let assert system.WriteFileBits("/project/data", <<255>>, _) =
    computer.write_file(origin, write_file.Input("data", <<255>>))
  let assert system.GenerateKey(_) = computer.create_key(create_key.Eddsa)
  let assert system.Now(_) = computer.extrinsic(harness.Now, origin)
  let assert system.Random(2, _) = computer.extrinsic(harness.Flip, origin)
}

pub fn binary_file_workflow_is_source_relative_in_the_sandbox_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_directory("/project")
    |> sandbox.with_cwd("/elsewhere")
  let workflow = {
    use written <- system.then(computer.write_file(
      origin,
      write_file.Input("data", <<255, 0>>),
    ))
    use Nil <- system.try(written)
    use appended <- system.then(computer.append_file(
      origin,
      append_file.Input("data", <<1, 2>>),
    ))
    use Nil <- system.try(appended)
    computer.read_file(origin, read_file.Input("data", 1, 99))
  }
  let assert #(sandbox.Returned(result), sandbox) =
    sandbox.run(workflow, sandbox)
  assert result == Ok(<<0, 1, 2>>)
  assert fs.read_bits(sandbox.file_system, "/project/data")
    == Ok(<<255, 0, 1, 2>>)
  let assert #(sandbox.Returned(entries), sandbox) =
    computer.read_directory(origin, ".") |> sandbox.run(sandbox)
  assert entries == Ok([#("data", read_directory.File(4))])
  let assert #(sandbox.Returned(deleted), sandbox) =
    computer.delete_file(origin, "data") |> sandbox.run(sandbox)
  assert deleted == Ok(Nil)
  let assert #(sandbox.Returned(missing), _) =
    computer.read_file(origin, read_file.Input("data", 0, 5))
    |> sandbox.run(sandbox)
  assert missing == Error(simplifile.describe_error(simplifile.Enoent))
}

pub fn read_directory_sorts_entries_and_includes_file_sizes_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_file_bits("/project/z", <<255, 1>>)
    |> sandbox.with_file("/project/a", "a")
    |> sandbox.with_directory("/project/sub")
  let assert #(sandbox.Returned(entries), _) =
    computer.read_directory(origin, ".") |> sandbox.run(sandbox)
  assert entries
    == Ok([
      #("a", read_directory.File(1)),
      #("sub", read_directory.Directory),
      #("z", read_directory.File(2)),
    ])
}

pub fn failed_path_resolution_never_requests_a_write_test() {
  let assert system.Cwd(resume) =
    computer.write_file(source.Inline, write_file.Input("file", <<1>>))
  assert resume(Error("cwd unavailable"))
    == system.Done(Error("cwd unavailable"))
  assert computer.write_file(
      source.Disk("/entry.eyg"),
      write_file.Input("../file", <<1>>),
    )
    == system.Done(Error("invalid relative path outside filesystem"))
}

pub fn environment_time_random_and_stdin_use_configured_sandbox_values_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_env("TOKEN", "local")
    |> sandbox.with_now(1234)
    |> sandbox.with_random_values([0, 7])
    |> sandbox.with_stdin("input")
  let workflow =
    system.traverse(
      [
        harness.Env("TOKEN"),
        harness.Env("MISSING"),
        harness.Now,
        harness.Flip,
        harness.Random(10),
        harness.StandardIn,
      ],
      computer.extrinsic(_, origin),
    )
  let assert #(sandbox.Returned(values), sandbox) =
    sandbox.run(workflow, sandbox)
  assert values
    == [
      v.Tagged("Some", v.String("local")),
      v.Tagged("None", v.unit()),
      v.Integer(1234),
      v.bool(True),
      v.Integer(7),
      v.ok(v.Binary(<<"input">>)),
    ]
  assert sandbox.random_values == []
  assert sandbox.stdin == []
}

pub fn outputs_keep_raw_writes_distinct_from_cli_lines_test() {
  let workflow = {
    use _ <- system.then(computer.extrinsic(harness.StanardOut("raw"), origin))
    use _ <- system.then(system.stdout(" line"))
    use _ <- system.then(computer.extrinsic(
      harness.StandardError("error"),
      origin,
    ))
    computer.extrinsic(harness.Sleep(5), origin)
  }
  let #(_, sandbox) = sandbox.run(workflow, sandbox.sandbox())

  assert sandbox.stderr == ["error"]
  assert sandbox.stdout == [" line", "raw"]
}

pub fn exit_does_not_resume_even_through_map_and_then_test() {
  let effect =
    computer.extrinsic(harness.Exit(7), origin)
    |> system.map(fn(_) { panic as "exit resumed map" })
    |> system.then(fn(_) { system.write_stdout("unreachable") })
  let #(outcome, _sandbox) = sandbox.run(effect, sandbox.sandbox())
  assert outcome == sandbox.Exited(7)
}

pub fn fetch_is_deferred_and_uses_the_configured_network_test() {
  let request = request.new() |> request.set_body(<<>>)
  let effect = computer.extrinsic(harness.Fetch(request), origin)
  let assert system.Fetch(_, _) = effect
  let sandbox =
    sandbox.sandbox()
    |> sandbox.save_and_return(
      response.new(200) |> response.set_body(<<"response">>),
    )
  let assert #(sandbox.Returned(value), sandbox) = sandbox.run(effect, sandbox)
  let assert v.Tagged("Ok", _) = value
  assert sandbox.network_state == [request]
}

pub fn json_parsing_and_hash_encoding_test() {
  let assert system.Done(v.Tagged("Ok", _)) =
    computer.extrinsic(harness.DecodeJson(<<"{}">>), origin)
  let assert system.Done(v.Tagged("Ok", _)) =
    computer.extrinsic(harness.EygParse("42"), origin)
  let assert #(sandbox.Returned(hashed), _) =
    computer.extrinsic(harness.Hash(hash.Input(hash.Sha256, <<"abc">>)), origin)
    |> sandbox.run(sandbox.sandbox())
  let assert v.Binary(bytes) = hashed
  assert bytes
    == <<
      186,
      120,
      22,
      191,
      143,
      1,
      207,
      234,
      65,
      65,
      64,
      222,
      93,
      174,
      34,
      35,
      176,
      3,
      97,
      163,
      150,
      23,
      122,
      156,
      180,
      16,
      255,
      97,
      242,
      0,
      21,
      173,
    >>
}

pub fn shared_ir_and_computer_cast_resume_an_interpreter_effect_test() {
  let program =
    ir.apply(
      ir.perform("ReadFile"),
      ir.record([
        #("path", ir.string("data")),
        #("offset", ir.integer(0)),
        #("limit", ir.integer(10)),
      ]),
    )
  let assert Error(#(break.UnhandledEffect(label, lift), meta, env, k)) =
    block.execute(program, [])
  let assert Ok(effect) = computer.cast(label, lift)
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_cwd("/project")
    |> sandbox.with_file("/project/data", "text")
  let assert #(sandbox.Returned(value), _) =
    computer.extrinsic(effect, meta.origin) |> sandbox.run(sandbox)
  let assert Ok(#(Some(value), _)) = block.resume(value, env, k)
  assert value == v.ok(v.Binary(<<"text">>))
}
