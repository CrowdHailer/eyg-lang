import eyg/ir/tree as ir
import gleam/crypto
import multiformats/cid/v1
import multiformats/hashes
import website/components/tree

pub fn reference_forms_render_distinctly_test() {
  let cid =
    v1.Cid(
      297,
      hashes.Multihash(
        hashes.Sha256,
        crypto.hash(crypto.Sha256, <<"module":utf8>>),
      ),
    )
  let encoded = v1.to_string(cid)

  assert ["content(" <> encoded <> ")"]
    == tree.lines(#(ir.Reference(ir.Content(cid)), Nil))
  assert ["package(standard)"]
    == tree.lines(#(ir.Reference(ir.Package("standard")), Nil))
  assert ["version(standard, 2)"]
    == tree.lines(#(ir.Reference(ir.Version("standard", 2)), Nil))
  assert ["release(standard, 2, " <> encoded <> ")"]
    == tree.lines(#(
      ir.Reference(ir.Pinned(ir.Release("standard", 2, cid))),
      Nil,
    ))
  assert ["relative(./local.eyg.json)"]
    == tree.lines(#(ir.Reference(ir.Relative("./local.eyg.json")), Nil))
}
