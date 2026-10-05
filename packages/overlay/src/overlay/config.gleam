import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value
import gleam/result
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama

/// Configuration that is common to any overlay agent, chat or otherwise
pub type Config(meta) {
  Config(
    llm: provider.Llm,
    policy: state.Value(meta),
    context: state.Value(meta),
  )
}

/// we can assume cast returns good values for policy and context because we should type check before hande
/// We need to extract the context type so it can be used as a module when evaluating
pub fn cast(value) {
  case
    cast.field("llm", cast_llm, value),
    cast.field("policy", Ok, value),
    cast.field("context", Ok, value)
  {
    Ok(provider), Ok(policy), Ok(context) -> {
      let llm = provider.Llm(provider:, model: "glm-5.3:cloud")
      Ok(Config(llm:, policy:, context:))
    }
    Error(reason), _, _ -> Error(reason)
    Ok(_), Error(reason), _ -> Error(reason)
    Ok(_), Ok(_), Error(reason) -> Error(reason)
  }
}

// cast is the wrong term, we need a decode API
fn cast_llm(value) {
  use tagged <- result.try(cast.as_tagged(value))
  case tagged {
    #("Ollama", inner) -> result.map(cast_ollama(inner), provider.Ollama)
    #(_, _) -> Error(break.NoMatch(value))
  }
}

fn cast_ollama(value) {
  use origin <- result.try(cast.field("origin", cast.as_string, value))
  use origin <- result.try(
    origin.from_string(origin)
    |> result.replace_error(break.IncorrectTerm("origin", value.String(origin))),
  )
  use api_key <- result.try(cast.field(
    "api_key",
    cast.as_option(_, cast.as_string),
    value,
  ))
  Ok(ollama.Config(origin:, api_key:))
}
