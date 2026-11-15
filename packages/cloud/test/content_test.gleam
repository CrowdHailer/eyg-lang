import api_test
import cloud/api
import cloud/beam/execute
import cloud/box
import cloud/box/check
import cloud/catalog
import cloud/content
import eyg/hub/cache
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/list
import gleeunit/should
import howdy
import howdy/testing
import multiformats/cid/v1
import ogre/origin

pub fn data_structures_are_checked_values_test() {
  let runtime =
    execute.State(origin.http("localhost"), cache.ready(), dict.new())
  list.each(
    [
      <<"{\"name\":\"Ada\",\"active\":true,\"count\":2,\"missing\":null}":utf8>>,
      <<"[1,\"two\",{\"three\":3},[false,{}]]":utf8>>,
      <<"{\"number\":1.25,\"bytes\":{\"/\":{\"bytes\":\"aGVsbG8\"}}}":utf8>>,
    ],
    fn(bytes) {
      let assert Ok(source) = content.source(content.dag_json_code, bytes)
      check.prepare(ir.map_annotation(source, fn(_) { #(0, 0) }), runtime)
      |> should.be_ok
    },
  )
  content.source(content.dag_json_code, <<"{\"/\":\"invalid CID\"}":utf8>>)
  |> should.be_error
}

pub fn staged_content_and_short_routes_test() {
  let #(service, app) = api_test.setup()
  let app = howdy.controller(app, api.short_controller(service))
  let assert Ok(owner) = catalog.create(service.catalog, "content", [])
  let before = box.inspect(owner).files.root
  let response =
    testing.request(http.Post, "/api/boxes/content/blocks")
    |> testing.bytes_body(<<"{\"answer\":42}":utf8>>)
    |> testing.header("content-type", "application/vnd.ipld.dag-json")
    |> testing.header("authorization", "Bearer test-admin")
    |> testing.send(app)
  response.status |> should.equal(200)
  let assert Ok(cid) =
    testing.json(response, decode.field("cid", decode.string, decode.success))
  box.inspect(owner).files.root |> should.equal(before)
  let response =
    testing.request(http.Put, "/content/answer.eyg")
    |> testing.bytes_body(<<
      "let data = #":utf8,
      cid:utf8,
      "\ndata.answer":utf8,
    >>)
    |> testing.header("if-match", v1.to_string(before))
    |> testing.header("authorization", "Bearer test-admin")
    |> testing.send(app)
  response.status |> should.equal(200)
  let files = box.inspect(owner).files
  let runtime =
    execute.State(origin.http("localhost"), cache.ready(), dict.new())
  let assert Ok(#(modules, _)) = check.validate(files, runtime)
  let assert Ok(module) = dict.get(modules, "/answer.eyg")
  module.value |> should.equal(v.Integer(42))
  let response =
    testing.get("/content/answer.eyg")
    |> testing.header("authorization", "Bearer test-admin")
    |> testing.send(app)
  response.status |> should.equal(200)
  let response =
    testing.post(
      "/content/transactions",
      json.object([
        #("base", json.string(v1.to_string(files.root))),
        #("changes", json.preprocessed_array([])),
      ]),
    )
    |> testing.send(app)
  response.status |> should.equal(400)
  box.inspect(owner).files.root |> should.equal(files.root)
  let assert Ok(raw) = box.stage(owner, content.raw, <<"reusable":utf8>>)
  let response =
    testing.post(
      "/content/transactions",
      json.object([
        #("base", json.string(v1.to_string(files.root))),
        #(
          "changes",
          json.preprocessed_array([
            json.object([
              #("operation", json.string("put")),
              #("path", json.string("/asset.txt")),
              #("reference", json.string(v1.to_string(raw))),
            ]),
          ]),
        ),
      ]),
    )
    |> testing.header("authorization", "Bearer test-admin")
    |> testing.send(app)
  response.status |> should.equal(200)
  let response =
    testing.get("/content/asset.txt")
    |> testing.header("authorization", "Bearer test-admin")
    |> testing.send(app)
  testing.text(response) |> should.equal("reusable")
}
