import cloud/beam/execute
import cloud/box
import cloud/box/check
import cloud/box/interface
import cloud/box/transaction as tx
import eyg/hub/cache
import gleam/bit_array
import gleam/dict
import gleeunit/should
import ogre/origin
import simplifile

pub fn invalid_interface_and_schedule_rejected_test() {
  let runtime =
    execute.State(origin.http("localhost"), cache.ready(), dict.new())
  let initial = box.empty()
  let assert Ok(policy) = simplifile.read("policy.eyg")
  let assert Ok(files) =
    tx.prepare(
      initial.files,
      initial.files.root,
      [
        tx.MakeDirectory("/system/cron"),
        tx.Put("/system/policy.eyg", bit_array.from_string(policy)),
        tx.Put("/system/http.eyg", <<
          "{handler: (_) -> { 42 }, policy: import \"policy.eyg\"}":utf8,
        >>),
      ],
      fn(_) { True },
    )
  let assert Ok(#(modules, runtime)) = check.validate(files, runtime)
  interface.validate(modules, runtime) |> should.be_error
  let assert Ok(files) =
    tx.prepare(
      files,
      files.root,
      [
        tx.Delete("/system/http.eyg"),
        tx.Put("/system/cron/bad.eyg", <<
          "{cron: \"invalid\", handler: (_) -> { {} }, policy: import \"/system/policy.eyg\"}":utf8,
        >>),
      ],
      fn(_) { True },
    )
  let assert Ok(#(modules, runtime)) = check.validate(files, runtime)
  interface.validate(modules, runtime) |> should.be_error
}
