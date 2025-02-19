import eyg/ir/cid
import gleam/io
import gleeunit/should
import website/sync/cache

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
  let cid = "baguqeera22cbouedtv3bzhajvp66ib6ichytfrid6osjpskyzthoivta6yyq"
  let cache = cache.init()
  cache.install_fragment(cache, cid, vacant_bytes)
  |> should.be_error
  |> io.debug
}

pub fn install_test() {
  let cache = cache.init()
  cache.install_fragment(cache, vacant_cid, vacant_bytes)
  |> should.be_ok
}
