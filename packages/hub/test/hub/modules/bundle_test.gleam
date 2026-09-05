import eyg/ir/car
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/list
import hub/cid
import hub/modules/bundle

pub fn shake_reorders_root_and_drops_unreachable_blocks_test() {
  let dependency = ir.integer(1)
  let dependency_cid = cid.from_tree(dependency)
  let root_source = ir.reference(dependency_cid)
  let root = cid.from_tree(root_source)
  let unreachable = ir.string("not referenced")
  let unreachable_cid = cid.from_tree(unreachable)
  let archive =
    car.Car(car.Header(1, [root]), [
      block(unreachable_cid, unreachable),
      block(dependency_cid, dependency),
      block(root, root_source),
    ])
  let assert Ok(upload) = car.encode(archive)

  let assert Ok(shaken) = bundle.shake(upload)
  assert bundle.blocks(shaken) |> list.map(fn(module) { module.0 })
    == [root, dependency_cid]
}

pub fn shake_follows_transitive_references_test() {
  let leaf = ir.integer(1)
  let leaf_cid = cid.from_tree(leaf)
  let dependency = ir.reference(leaf_cid)
  let dependency_cid = cid.from_tree(dependency)
  let root_source = ir.reference(dependency_cid)
  let root = cid.from_tree(root_source)
  let archive =
    car.Car(car.Header(1, [root]), [
      block(root, root_source),
      block(leaf_cid, leaf),
      block(dependency_cid, dependency),
    ])
  let assert Ok(upload) = car.encode(archive)

  let assert Ok(shaken) = bundle.shake(upload)
  assert bundle.blocks(shaken) |> list.map(fn(module) { module.0 })
    == [root, dependency_cid, leaf_cid]
}

pub fn shake_rejects_a_missing_root_test() {
  let root = cid.from_tree(ir.integer(1))
  let archive = car.Car(car.Header(1, [root]), [])
  let assert Ok(upload) = car.encode(archive)

  assert bundle.shake(upload) == Error(bundle.MissingRoot(root))
}

fn block(cid, source) {
  #(cid, dag_json.to_block(source))
}
