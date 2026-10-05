import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value
import gleam/result
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/policy

/// Configuration that is common to any overlay agent, chat or otherwise
pub type Config(effect, meta) {
  Config(
    llm: provider.Llm,
    policy: policy.Policy(effect, meta),
    context: state.Value(meta),
  )
}

pub fn type_(rules, level, bindings) {
  let #(agent_context, bindings) = binding.mono(level, bindings)
  let ollama =
    t.record([
      #("origin", t.String),
      #("api_key", t.option(t.String)),
    ])
  let llm =
    t.record([
      #("provider", t.union([#("Ollama", ollama)])),
      #("model", t.String),
    ])
  let type_ =
    t.record([
      #("llm", llm),
      #("policy", policy.type_(rules)),
      #("context", agent_context),
    ])
  #(type_, bindings)
}

/// Decode configuration using the host's selected effect interfaces and rules.
/// Context remains an EYG value for use by agent programs.
pub fn cast(value, rules) {
  case
    cast.field("llm", cast_llm, value),
    cast.field("policy", policy.decode_policy(rules, _), value),
    cast.field("context", Ok, value)
  {
    Ok(llm), Ok(policy), Ok(context) -> {
      Ok(Config(llm:, policy:, context:))
    }
    Error(reason), _, _ -> Error(reason)
    Ok(_), Error(reason), _ -> Error(reason)
    Ok(_), Ok(_), Error(reason) -> Error(reason)
  }
}

// cast is the wrong term, we need a decode API
fn cast_llm(value) {
  use provider <- result.try(cast.field("provider", cast_provider, value))
  use model <- result.try(cast.field("model", cast.as_string, value))
  Ok(provider.Llm(provider:, model:))
}

fn cast_provider(value) {
  use tagged <- result.try(cast.as_tagged(value))
  case tagged {
    #("Ollama", inner) -> result.map(cast_ollama(inner), provider.Ollama)
    #(_, _) -> Error(break.NoMatch(value))
  }
}

fn cast_ollama(value) {
  use origin <- result.try(cast.field("origin", cast.as_string, value))
  use origin <- result.try(
    origin.from_string_strict(origin)
    |> result.replace_error(break.IncorrectTerm("origin", value.String(origin))),
  )
  use api_key <- result.try(cast.field(
    "api_key",
    cast.as_option(_, cast.as_string),
    value,
  ))
  Ok(ollama.Config(origin:, api_key:))
}
