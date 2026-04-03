import eyg/hub/schema
import eyg/ir/dag_json
import gleam/json

pub fn share_response_test() {
  let response = dag_json.vacant_cid
  assert Ok(response)
    == schema.share_response_encode(response)
    |> json.to_string
    |> json.parse(schema.share_response_decoder())
}
