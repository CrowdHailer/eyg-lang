import eyg/cli/helpers
import eyg/cli/internal/source
import eyg/cli/share
import eyg/hub/schema
import eyg/ir/dag_json
import gleam/bit_array
import gleam/http/response
import gleam/json
import multiformats/cid/v1

pub fn share_simple_expression_test() {
  let sandbox =
    helpers.sandbox()
    |> helpers.with_network(
      fn(request, acc) {
        #(
          response.new(200)
            |> response.set_body(
              schema.share_response_encode(dag_json.vacant_cid)
              |> json.to_string
              |> bit_array.from_string,
            )
            |> Ok,
          [request, ..acc],
        )
      },
      [],
    )
  let input = source.Code("3")
  let #(output, sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert Ok(0) == output
  assert [v1.to_string(dag_json.vacant_cid)] == sandbox.stdout
}
