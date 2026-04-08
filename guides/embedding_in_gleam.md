# Embedding EYG in Gleam programs

EYG is type safe scripting language with managed side effects.
It makes a great language for many different environments, including being embedded in other languages.
This post walks through embedding EYG into [Gleam](https://gleam.run).
Gleam itself is a language that unusually covers two great runtimes namely JavaScript and erlang.

## Why embed

If you are familiar with [Lua](https://www.lua.org/) you may already have a usecase in mind.
An embedded scripted language opens a programmable interface to your application without the security vulnerabilities that would arise if you let users modify the source code.
This scripting can be for simple configuration or a rich plugin or modding system.

## Getting started

EYG's toolkit consists of a set of composable parts, for these examples we will need all the following parts

```sh
gleam add eyg_analysis eyg_interpreter eyg_parser touch_grass
```

## A pure program

Let's start with a simple configuration script.

```js
let name = "Angelos"
let timeout = !int_multiply(15, 60)
{name: name, timeout: timeout}
```

This configuration example would be ok without a programming language,
but it's nice that we can clarify that we want 15 minutes by saying 15 times 60.

To run this configuration script in gleam we need the following.

```gleam
import eyg/parser
import eyg/interpreter/expression as r

pub fn run(code) {
  let assert Ok(source) = parser.all_from_string(code)
  let state = Nil
  let scope = []
  loop(r.execute(source, scope), state)
}

pub fn loop(return, state) {
   case return {
    Ok(value) -> Ok(value)
    Error(#(reason, _meta, env, k)) -> Error(reason)
   }
}
```

This is all the code required to implement an EYG runner in Gleam.

- The module `eyg/interpreter/expression` is imported as `r` for runner. The interpreter library also exposes a block interpreter that can be used to implement shells/REPLs. We won't cover that in this post.
- EYG code can be written using a structural editor rather than writing text files. In that case you wouldn't need the parser but would need to check out the  `tree` module for decoding the JSON version of the intermediate representation (IR)
- The `loop` function is a recursive loop that will call itself to handle effects and imports. This pure config example doesn't need them but we will introduce them shortly

## My first effect

Our pure EYG runner cannot perform any side effect.
This is good enough for configuration but for anything more it is very limited.
Even the hello world program below would return an error in our first runner.

```js
perform Log("Hello, world!")
```

Let's create a runner that allows scripts log messages during their execution.

```gleam
import eyg/parser
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/result.{try}

pub fn run(code) {
  let assert Ok(source) = parser.all_from_string(code)
  let state = Nil
  let scope = []
  loop(r.execute(source, scope), state)
}

pub fn loop(return, state) {
   case return {
    Ok(value) -> Ok(value)
    Error(#(reason, _meta, env, k)) -> case reason {
       break.UnhandledEffect("Log", lift) -> {
          use message <- try(cast.as_string(lift))
          io.println(message)
          loop(r.resume(v.unit(), env, k), state)
        }
      _ -> Error(reason)
    }
   }
}
```

Our new runner has a single effect implementation for `Log`.
When a script performs the effect the runner gets a break value for `UnhandledEffect`. 

To handle an effect first cast the value into the correct gleam type, in this case a string.
Actually do the effect in the outside world, print a log line with the message.
Resume the program with a returned value for the effect.
In this case resume with the unit value.
Unit is an empty record and the EYG equivalent of a Nil.

This runner only handles the `Log` effect.
For all other effects we correctly return the break as an error.
This is what makes EYG safe for scripting, it is not possible for someone to write a program that reads the file system or talks to the internet unless given explicit permission through an effect.

This is what it means for EYG to have managed effects.

## Effects aren't side effects, unless we want them to be.

Our previous runner directly mapped `Log` effects to an io write.
The EYG script didn't require this, all that is required is that a handler exists that accepts a string an resumes the script.

We might want to run this script but put the messages somewhere, or nowhere.
This pattern is particularly useful for testing, instead of mocking side effects the list of messages can be compared with what's expected directly.


```gleam
import eyg/parser
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/break
import eyg/interpreter/value as v

pub fn run(code) {
  let assert Ok(source) = parser.all_from_string(code)
  let state = []
  let scope = []
  loop(r.execute(source, scope), state)
}

pub fn loop(return, state) {
   case return {
    // Return the final value of the script and all messages logged along the way.
    Ok(value) -> Ok(#(value, list.reverse(state)))
    Error(#(reason, _meta, env, k)) -> case reason {
       break.UnhandledEffect("Log", lift) -> {
          use message <- result.try(cast.as_string(lift))
          // Our state is now a record of all messages that have happened
          let state = [message,..state]
          loop(r.resume(v.unit(), env, k), state)
        }
      _ -> Error(reason)
    }
   }
}
```


This next runner handles `Log` effects by collecting all the logged messages without performing any side effects.

## Adding more effects

With EYG it's easy to create runners for lots of environments with specific effects. 
However, there are some effects that look the same in many environments.
The `touch_grass` package defines reusable logic for these common effects.
For example let's add our second effect.

```gleam
import eyg/parser
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/break
import eyg/interpreter/value as v
import touch_grass/fetch

pub fn run(code) {
  let assert Ok(source) = parser.all_from_string(code)
  let state = Nil
  let scope = []
  loop(r.execute(source, scope), state)
}

pub fn loop(return, state) {
   case return {
    Ok(value) -> Ok(value)
    Error(#(reason, _meta, env, k)) -> case reason {
      break.UnhandledEffect("Log", lift) -> // similar to before
      break.UnhandledEffect("Fetch", lift) -> {
          use request <- try_sync(fetch.decode(lift))
          use result <- promise.await(send_bits(request))
          let result = result.map_error(result, string.inspect)
          loop(r.resume(fetch.encode(result), env, k), state)
      }
      _ -> Error(reason)
    }
   }
}

fn try_sync(result, then) {
  case result {
    Ok(value) -> then(value)
    Error(reason) -> promise.resolve(Error(reason))
  }
}

pub fn send_bits(request) {
  use response <- promise.try_await(fetch.send_bits(request))
  fetch.read_bytes_body(response)
}
```

This runner will handle EYG scripts with a `Log` or `Fetch` effect.
The fetch effect needs to be called with a request, and returns a response.
A request is a record with fields for method, scheme, host, port, path, query, headers and body.
Writing a decoder for all these fields is tedious.
Also helpful for the fetch effect to be consistent across runners.
Using encode and decode from the `touch_grass/fetch` module will ensure that your fetch implementation is consistent.

## Typing effects

Right at the top I called EYG type safe yet have not mentioned about type checking.
The runners so far have all returned a result to handle the case of the program erroring.

EYG implements sound structural type inference including inference of all effect types.

Running this type checker is optional
For a script that is intended to run and finish type checking before running the script doesn't add much.
In most other circumstances asserting that the EYG program has no runtime errors is invaluable.

```gleam
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t

pub fn check(source){
  let context =
    infer.pure()
    |> infer.with_effect("Log", t.String, t.unit)

  let analysis = infer.check(context, source)
  case infer.all_errors(analysis) {
    // No errors return principle type
    [] -> Ok(infer.type_(analysis))
    errors -> Error(errors)
  }
}
```

This function type checks the source in an environment with only the `Log` effect.
`infer.unpure()` will allow any effect, useful for checking libraries where you don't yet know the context they will run in.

