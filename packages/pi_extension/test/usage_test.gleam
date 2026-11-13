import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import pi_extension
import pi_extension/native as n

fn data(text) {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

pub fn nested_usage_includes_tokens_caches_and_fractional_costs_test() {
  let first =
    data(
      "{\"input\":2,\"output\":3,\"cacheRead\":5,\"cacheWrite\":7,\"totalTokens\":17,\"cost\":{\"input\":0.1,\"output\":0.2,\"cacheRead\":0.3,\"cacheWrite\":0.4,\"total\":1.0}}",
    )
  let combined = pi_extension.add_usage(Some(first), first)
  assert pi_extension.add_usage(None, first) == first
  assert n.field(combined, "input") == n.data(4)
  assert n.field(combined, "output") == n.data(6)
  assert n.field(combined, "cacheRead") == n.data(10)
  assert n.field(combined, "cacheWrite") == n.data(14)
  assert n.field(combined, "totalTokens") == n.data(34)
  assert n.field(n.field(combined, "cost"), "total") == n.data(2.0)
  assert n.field(n.field(combined, "cost"), "cacheRead") == n.data(0.6)
}
