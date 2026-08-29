//// The harness describes all the effects available in an execution environment.
//// This is similar to the Hardware Abstraction Layer (HAL) from the rust ecosystem.
//// Or platforms in from Roc ecosystem.
//// 
//// The touch grass library consists of modules that specify individual interfaces to the platform.
//// For example Log, with definitions for types and casting values.
//// 
//// The browser workspace/environment is a collection of all effects available in the browser platform.
//// The browser workspace can look very similar to the cli workspace, but might have a different implementation.
//// 
//// The harness specification is not shared with the cli specification because there are a few differences in effects available.
//// Consistency accross platforms is managed by resusing touch_grass interfaces

import eyg/analysis/type_/isomorphic as t
import gleam/http/request.{type Request}
import gleam/uri
import ogre/operation
import touch_grass as tg
import touch_grass/download
import touch_grass/http
import touch_grass/interface.{Interface}

pub type Effect {
  Abort(String)
  Alert(String)
  Copy(String)
  DecodeJson(BitArray)
  Download(download.Input)
  Fetch(Request(BitArray))
  Flip
  Now
  Paste
  Print(String)
  Prompt(String)
  Random(Int)
  // TODO requires browser sleep
  // Sleep(Int)
  Visit(uri.Uri)
  // All Spotless effects
  Spotless(service: Service, operation: operation.Operation(BitArray))
}

pub type Service {
  DNSimple
  GitHub
  Vimeo
}

pub fn effect_label(service: Service) -> String {
  case service {
    DNSimple -> "DNSimple"
    GitHub -> "GitHub"
    Vimeo -> "Vimeo"
  }
}

// Geolocation shouldn't depend on plinth
// Now shouldn't be a string
// Prompt should work as a Readline in the cli
// OAuth 2.0 + MCP can be another effect if no server registration is required

fn spotless(service: Service) -> interface.Interface(Effect, a) {
  Interface(
    name: effect_label(service),
    lift_type: http.operation(),
    lower_type: t.result(http.response(), t.String),
    decode: http.operation_to_gleam,
  )
  |> tg.map(fn(operation) { Spotless(service:, operation:) })
}

// running them resumes with a function that takes a v.value.
// We don't need to pass around the encode
// 
// examples can use a smaller number of effects, down to zero,
// but continue to use this type.
pub fn effects() -> interface.Harness(Effect, a) {
  [
    tg.abort() |> tg.map(Abort),
    tg.alert() |> tg.map(Alert),
    tg.copy() |> tg.map(Copy),
    tg.decode_json() |> tg.map(DecodeJson),
    tg.download() |> tg.map(Download),
    tg.fetch() |> tg.map(Fetch),
    tg.flip() |> tg.replace(Flip),
    tg.now() |> tg.replace(Now),
    tg.paste() |> tg.replace(Paste),
    tg.print() |> tg.map(Print),
    tg.prompt() |> tg.map(Prompt),
    // tg.sleep() |> tg.map(Sleep),
    tg.random() |> tg.map(Random),
    tg.visit() |> tg.map(Visit),
    spotless(DNSimple),
    spotless(GitHub),
    spotless(Vimeo),
  ]
}
