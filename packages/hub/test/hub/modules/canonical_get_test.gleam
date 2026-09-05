import eyg/hub/client
import eyg/ir/tree as ir
import gleam/string
import hub/helpers.{dispatch}
import multiformats/cid/v1
import ogre/operation

pub fn fetch_accepts_an_alternate_cid_base_test() {
  use context <- helpers.web_context()
  let source = ir.integer(42)
  let response = dispatch(client.share_module(source), context)
  let assert Ok(cid) = client.share_response(response)
  let canonical = v1.to_string(cid)
  let alternate = "b" <> string.uppercase(string.drop_start(canonical, 1))

  let response = dispatch(operation.get("/modules/" <> alternate), context)
  assert response.status == 200
}
