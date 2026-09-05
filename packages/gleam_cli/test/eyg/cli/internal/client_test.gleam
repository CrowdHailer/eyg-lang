import eyg/cli/helpers
import eyg/cli/internal/client
import eyg/ir/tree as ir

pub fn share_module_rejects_an_incorrect_response_cid_test() {
  let sandbox =
    helpers.sandbox()
    |> helpers.save_and_return(helpers.vacant_cid_response())
  let #(result, _) =
    client.share_module(ir.integer(1), helpers.config.client)
    |> helpers.run(sandbox)

  assert result == Error("hub returned the wrong shared module ID")
}
