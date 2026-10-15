import channel_policy/engine
import channel_policy/identity
import channel_policy/mock
import channel_policy/quota
import gleam/int
import gleam/io
import gleam/list

pub fn main() {
  let assert Ok(evaluator) = engine.load("policies/llm_quota.eyg", 100_000)
  let assert Ok(session) = mock.login("ada-code")
  let account = identity.Account("T_ACME", "U_ADA")
  let limit = quota.Limit(account, "/v1/inference", "2026-10", 50)
  list.each([49, 50], fn(used) {
    let usage = quota.Usage(account, "/v1/inference", "2026-10", used, 1000)
    let result =
      quota.authorize_with_proofs(
        evaluator,
        session,
        usage,
        limit,
        "/v1/inference",
        "2026-10",
        1002,
        60,
      )
    let decision = case result {
      Ok(_) -> "ALLOW: reserve one request, then forward to the model"
      Error(reason) -> "DENY: " <> reason
    }
    io.println(int.to_string(used) <> "/50 requests: " <> decision)
    case result {
      Ok(permissions) ->
        list.each(permissions, fn(permission) {
          io.println(engine.describe(permission.tree))
        })
      Error(_) -> Nil
    }
  })
}
