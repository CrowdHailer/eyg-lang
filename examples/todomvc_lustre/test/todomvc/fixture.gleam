import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/interpreter/expression
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/json
import multiformats/cid/v1
import sha256
import simplifile
import todomvc/run
import todomvc/tasks

/// A cache holding the repository's copy of `@standard`, instead of the hub's.
pub fn standard() {
  let assert Ok(bytes) =
    simplifile.read_bits("../../eyg_packages/standard/index.eyg.json")
  let assert Ok(source) = json.parse_bits(bytes, dag_json.decoder(Nil))
  let source = ir.map_annotation(source, fn(_) { #(0, 0) })
  let assert infer.Done(analysis) = infer.check(infer.pure(), source)
  let assert Ok(value) = expression.execute(source, [])
  let assert Ok(#(cid, _)) =
    v1.from_string(
      "baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja",
    )
  let computed =
    cid.from_tree(source, fn(bytes) {
      fn(resume) { resume(sha256.hash(bytes)) }
    })(fn(cid) { cid })
  assert computed == cid
  let module = cache.Module(value:, type_: infer.poly_type(analysis))
  let entry =
    cache.Entry(version: 1, module: cid, cursor: 1, sequence: 1, cid: cid)
  cache.Cache(
    ..cache.empty(),
    modules: dict.from_list([#(cid, module)]),
    packages: dict.from_list([#("standard", entry)]),
    releases: dict.from_list([#(#("standard", 1), cid)]),
  )
}

pub fn shell() {
  let assert Ok(library) = simplifile.read("library.eyg")
  let assert Ok(shell) = run.start(library, standard())
  shell
}

pub fn tasks() {
  tasks.from_titles([
    "Buy milk #shopping",
    "Call the plumber",
    "Buy bread #shopping",
    "Write the EYG post #work",
  ])
}
