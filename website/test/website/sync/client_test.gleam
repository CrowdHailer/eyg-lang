import gleam/javascript/promise
import gleeunit/should
import website/sync/client.{Remote}

const vacant_bytes = <<"{\"0\":\"z\"}">>

const vacant_cid = "baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma"

pub fn fetch_valid_fragment_test() {
  let remote = Remote(no_index, fn(_) { promise.resolve(Ok(vacant_bytes)) })
  let #(client, _) = client.init(remote)
  let #(client, task) = client.fetch_fragments(client, [vacant_cid])
  let assert [run] = client.run(task)
  use result <- promise.map(run)
  let assert client.FragmentFetched(c, Ok(bytes)) = result
  c
  |> should.equal(vacant_cid)
  bytes
  |> should.equal(vacant_bytes)
}

pub fn remote_returns_incorrect_bytes_test() {
  let remote = Remote(no_index, fn(_) { promise.resolve(Ok(vacant_bytes)) })
  let #(client, _) = client.init(remote)
  let asked = "baguqeera22cbouedtv3bzhajvp66ib6ichytfrid6osjpskyzthoivta6yyq"
  let #(client, task) = client.fetch_fragments(client, [asked])
  let assert [run] = client.run(task)
  use result <- promise.map(run)
  let assert client.FragmentFetched(c, Error(reason)) = result
  c
  |> should.equal(asked)
  reason
  |> should.equal(client.DigestIncorrect)
}

fn no_index() {
  panic as "shouldn't be run in fragment tests"
}
