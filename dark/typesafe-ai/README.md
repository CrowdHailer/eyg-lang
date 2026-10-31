# TypeSafe AI

An EYG client for TypeSafe's Jev model, following the [Gleam library](../../packages/intelligence/README.md): pair questions with their answer decoders, combine them with `and`, and use `return` to define a typed result. The standard customer-triage example below evaluates urgency, selects a team, and scores frustration in one request, returning `{urgency, team, frustration}` as `body.answer` inside `Ok(Success({status, headers, body}))`, alongside the model and token usage. Set `TYPESAFE_AI_TOKEN` and run the example from the repository root; numeric answers are decimal strings, and choice answers are application values such as `Billing({})`.

```eyg
let jev = import "./dark/typesafe-ai/index.eyg"
let token = match perform Env("TYPESAFE_AI_TOKEN") {
  Some(token) -> { token }
  None(_) -> { !never(perform Abort("Set TYPESAFE_AI_TOKEN")) }
}
let config = jev.from_token(token)
let bundle = jev.and(
  jev.noul("Does this message need urgent attention?", None({}), None({})),
  (urgency) -> {
    jev.and(jev.choice("Which team should handle this message?", [
      jev.option("billing", Billing({}), "Payments, invoicing, refunds"),
      jev.option("technical", Technical({}), "Bugs, outages, integrations"),
      jev.option("sales", Sales({}), "Pricing, upgrades, new accounts")
    ], Billing({})), (team) -> {
      jev.and(jev.score("How frustrated is the customer?", [
        "Calm", "Frustrated", "Very angry"
      ]), (frustration) -> {
        jev.return({urgency, team: team.choice, frustration: frustration.score})
      })
    })
  }
)
jev.evaluate(config, "I was charged twice and need a refund today!", bundle)
```
