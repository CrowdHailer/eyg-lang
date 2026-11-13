/// Example admission policy for a metered LLM inference endpoint.
/// The caller reads Usage and Limit from trusted storage, never request JSON.
import channel_policy/engine.{type Engine}
import channel_policy/identity.{type Account, type Session}
import eyg/interpreter/value as v
import gleam/result

pub type Usage {
  Usage(
    account: Account,
    endpoint: String,
    window: String,
    calls: Int,
    observed_at: Int,
  )
}

pub type Limit {
  Limit(account: Account, endpoint: String, window: String, calls: Int)
}

/// Before forwarding an inference request, reserve a call in the same storage
/// transaction as this decision. The pure rule alone does not serialize callers.
pub fn authorize(
  evaluator: Engine,
  session: Session,
  usage: Usage,
  limit: Limit,
  endpoint: String,
  window: String,
  now: Int,
  max_age: Int,
) -> Result(Nil, String) {
  authorize_with_proofs(
    evaluator,
    session,
    usage,
    limit,
    endpoint,
    window,
    now,
    max_age,
  )
  |> result.map(fn(_) { Nil })
}

pub fn authorize_with_proofs(
  evaluator: Engine,
  session: Session,
  usage: Usage,
  limit: Limit,
  endpoint: String,
  window: String,
  now: Int,
  max_age: Int,
) -> Result(List(engine.Permission), String) {
  use account <- result.try(identity.account(session, now))
  use _ <- result.try(
    case
      max_age <= 0
      || now < usage.observed_at
      || now - usage.observed_at >= max_age
    {
      True -> Error("Usage snapshot is stale or invalid")
      False -> Ok(Nil)
    },
  )
  let usage_fact =
    engine.record([
      #("tenant", v.String(usage.account.workspace)),
      #("actor", v.String(usage.account.user)),
      #("resource", v.String(usage.endpoint)),
      #("window", v.String(usage.window)),
      #("used", v.Integer(usage.calls)),
    ])
  let quota_fact =
    engine.record([
      #("tenant", v.String(limit.account.workspace)),
      #("actor", v.String(limit.account.user)),
      #("resource", v.String(limit.endpoint)),
      #("window", v.String(limit.window)),
      #("limit", v.Integer(limit.calls)),
      #("policy", v.String("llm-usage-limit")),
    ])
  let request =
    engine.record([
      #("tenant", v.String(account.workspace)),
      #("actor", v.String(account.user)),
      #("action", v.String("infer")),
      #("resource", v.String(endpoint)),
      #("window", v.String(window)),
    ])
  use proofs <- result.try(engine.authorize_with_proofs(
    evaluator,
    engine.facts([#("Usage", [usage_fact]), #("Quota", [quota_fact])]),
    request,
  ))
  case proofs {
    [] -> Error("Inference denied: usage limit reached or quota does not match")
    _ -> Ok(proofs)
  }
}
