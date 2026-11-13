import eyg/hub/cache
import eyg/ir/tree as ir
import gleam/dict
import gleam/http
import gleam/option.{None}
import loam/execute
import loam/sandbox
import multiformats/cid/v1
import ogre/origin

pub fn known_release_metadata_does_not_contact_the_hub_test() {
  let assert Ok(#(cid, _)) =
    v1.from_string(
      "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
    )
  let cache =
    cache.Cache(
      ..cache.empty(),
      packages: dict.from_list([#("demo", cache.Entry(2, cid, 1, 0, cid))]),
      releases: dict.from_list([#(#("demo", 2), cid)]),
    )
  let runtime =
    execute.State(origin.Origin(http.Https, "eyg.run", None), cache, None)
  let assert #(sandbox.Returned(#(Ok(release), _)), _) =
    execute.latest_release("demo", runtime) |> sandbox.run(sandbox.sandbox())
  assert release == ir.Release("demo", 2, cid)
  let assert #(sandbox.Returned(#(Ok(found), _)), _) =
    execute.version_module("demo", 2, runtime) |> sandbox.run(sandbox.sandbox())
  assert found == cid
}
