import eyg/sync/seed
import eygir/encode
import eygir/expression
import gleeunit/should
import midas/task as t

pub fn load_seeds_test() {
  let task = seed.from_dir("seed")
  let #(path, r) = should.be_ok(t.expect_list(task))
  path
  |> should.equal("seed")
  let reply = Ok(["foo", "bar"])
  let #(path, r) = should.be_ok(t.expect_list(r(reply)))
  path
  |> should.equal("seed/foo")
  // depth first
  let reply = Ok([])
  let #(path, r) = should.be_ok(t.expect_list(r(reply)))
  path
  |> should.equal("seed/bar")
  let reply = Ok(["a.json"])
  let #(path, r) = should.be_ok(t.expect_read(r(reply)))
  path
  |> should.equal("seed/bar/a.json")

  let lib = expression.Integer(12)

  let reply = Ok(<<encode.to_json(lib):utf8>>)

  let files = should.be_ok(t.expect_done(r(reply)))
  files
  |> should.equal([#("/references/@bar.a.json", <<"{\"0\":\"i\",\"v\":12}">>)])
}
