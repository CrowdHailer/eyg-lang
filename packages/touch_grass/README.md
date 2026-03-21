# Touch Grass

Common effect definitions for your Eat Your Greens (EYG) runtime.

[![Package Version](https://img.shields.io/hexpm/v/touch_grass)](https://hex.pm/packages/touch_grass)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/touch_grass/)

Every interaction between an EYG program and the outside world is managed via an [effect](https://crowdhailer.me/2025-02-14/algebraic-effects-are-a-functional-approach-to-manage-side-effects/). This includes filesystems, network sockets, clocks, randomness, environment variables and anything else.

**Note**, this library defines only interfaces, the types and encode/decode functions, not a concrete implementation.
Your runtime will need to do that.

## Usage

```sh
gleam add touch_grass
```

This example creates an EYG runner that allows programs to talk to the outside world via the `Fetch` effect.

```gleam
import eyg/interpreter/break
import eyg/interpreter/expression as r
import eyg/interpreter/value
import gleam/fetch
import gleam/string

/// Accept the source as an EYG IR tree
pub fn run(source) {
  let scope = []
  loop(r.execute(source, scope))
}

/// Handle the raised effect if it is a fetch effect and resume.
/// Treat all other break reasons as an error.
fn loop(return) {
  case return {
    Ok(value) -> promise.resolve(Ok(value))
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UnhandledEffect("Fetch", lift) ->
          case fetch.decode(lift) {
            Ok(request) ->
              loop(r.resume(fetch.encode(do_fetch(request)), env, k))
            Error(reason) -> promise.resolve(Error(reason))
          }
        _ -> promise.resolve(Error(reason))
      }
  }
}

fn do_fetch(request)  {
  send_bits(request)
  |> result.map_error(string.inspect)
}

fn send_bits(request) {
  use response <- promise.try_await(fetch.send_bits(request))
  fetch.read_bytes_body(response)
}

```

## Design principles

- **Sync effects:** Concurrency and async execution are concerns of the runtime, not the interface contract.
- **Errors are values:** Every fallible operation returns a `Result`, EYG has no support for panics or exceptions. 
- **Independent effects** A runtime can compose any subset of the effects defined in this library.

The `touch_grass` library is influenced by patterns like Hardware Abstraction Layer (HAL) and ports and adapters.