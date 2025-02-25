import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/tree as ir
import gleam/dict
import gleam/io
import gleeunit/should
import website/sync/cache

fn should_have_value(cache: cache.Cache, ref, value) {
  cache.fragments
  |> dict.get(ref)
  |> should.be_ok
  |> fn(f: cache.Fragment) { f.value }()
  |> should.equal(Ok(value))
}

pub fn install_invalid_block_test() {
  let bytes = <<"Not code">>
  let cid = cid.from_block(bytes)
  let cache = cache.init()
  cache.install_fragment(cache, cid, bytes)
  |> should.be_error
  |> io.debug
}

const vacant_bytes = <<"{\"0\":\"z\"}">>

const vacant_cid = "baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma"

pub fn install_incorrect_cid_test() {
  todo as "need browser validation check"
  let cid = "baguqeera22cbouedtv3bzhajvp66ib6ichytfrid6osjpskyzthoivta6yyq"
  let cache = cache.init()
  cache.install_fragment(cache, cid, vacant_bytes)
  |> should.be_error
}

pub fn install_test() {
  let cache = cache.init()
  cache.install_fragment(cache, vacant_cid, vacant_bytes)
  |> should.be_ok
}

pub fn resolve_references_test() {
  // top depends on a, a and b depend on x
  let top = ir.multiply(ir.reference("a"), ir.integer(2))
  let a = ir.add(ir.reference("x"), ir.integer(1))
  let b = ir.add(ir.reference("x"), ir.integer(2))
  let cache =
    cache.init()
    |> cache.install_source("top", top)
    |> cache.install_source("a", a)
    |> cache.install_source("b", b)

  cache.fragments
  |> dict.get("a")
  |> should.be_ok
  |> fn(f: cache.Fragment) { f.value }()

  let cache =
    cache
    |> cache.install_source("x", ir.integer(10))
  cache
  |> should_have_value("x", v.Integer(10))
  cache
  |> should_have_value("a", v.Integer(11))
  cache
  |> should_have_value("b", v.Integer(12))
  cache
  |> should_have_value("top", v.Integer(22))
}
// pub fn resolve_release_test()  {
//   let dep = ir.string("first published release")

//   todo
// }
// resolve releases
