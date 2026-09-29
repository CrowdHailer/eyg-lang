import eyg/cli/helpers
import eyg/cli/internal/store
import eyg/ir/dag_json
import gleam/json
import gleam/list
import kryptos/eddsa
import loam/sandbox
import loam/system
import multiformats/cid/v1

pub fn malformed_keypairs_return_credential_errors_test() {
  list.each(
    [json.string(""), json.string("not a PEM key"), json.int(42)],
    fn(keypair) {
      let credential =
        json.object([
          #("principal", json.string(v1.to_string(dag_json.vacant_cid))),
          #("keypair", keypair),
        ])
        |> json.to_string
      let sandbox =
        sandbox.sandbox()
        |> sandbox.with_file("/eyg/signatories/local.json", credential)
      let assert #(sandbox.Returned(Error("invalid local credential")), _) =
        sandbox.run(store.read_signatory("local", helpers.config.dirs), sandbox)
    },
  )
}

pub fn saved_keypair_roundtrips_test() {
  let workflow = {
    use keypair <- system.then(system.generate_key())
    let signatory = store.Signatory("local", dag_json.vacant_cid, keypair)
    use saved <- system.then(store.save_signatory(
      signatory,
      helpers.config.dirs,
    ))
    let assert Ok(Nil) = saved
    use loaded <- system.map(store.read_signatory("local", helpers.config.dirs))
    #(signatory, loaded)
  }
  let assert #(sandbox.Returned(#(original, Ok(loaded))), _) =
    sandbox.run(workflow, sandbox.sandbox())
  assert loaded.alias == original.alias
  assert loaded.principal == original.principal
  assert loaded.keypair.key_id == original.keypair.key_id
  assert eddsa.to_pem(loaded.keypair.private_key)
    == eddsa.to_pem(original.keypair.private_key)
}
