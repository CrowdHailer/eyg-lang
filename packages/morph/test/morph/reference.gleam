import eyg/ir/tree as ir
import multiformats/cid/v1

pub fn cid() {
  let assert Ok(#(cid, <<>>)) =
    v1.from_string(
      "baguqeerat6kjk2gjedpjcv4tuh5qiozijzgbhenep5cjfbe7vgc2ehjcqlma",
    )
  cid
}

pub fn all() {
  let cid = cid()
  [
    ir.Content(cid),
    ir.Package("standard"),
    ir.Version("standard", 3),
    ir.Pinned(ir.Release("standard", 3, cid)),
    ir.Relative("./module.eyg"),
  ]
}
