import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/debug
import eyg/parser/parser.{type Reason} as _
import gleam/dynamic/decode
import gleam/list
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import pal/platform/browser
import pal/system
import touch_grass/harness/browser as harness

pub type Context {
  Context(
    cache: cache.Cache(Meta),
    counter: Int,
    effects: List(system.Effect(#(Int, state.Value(Meta)))),
  )
}

pub type Meta =
  List(Int)

/// The running state of a given tool call
pub type Call {
  UnknownTool(name: String)
  BadArguments(List(decode.DecodeError))
  InvalidCode(Reason)
  Successful(state.Value(Meta))
  Exception(state.Reason(Meta))
  Aborted(String)
  Handling(task_id: Int, env: state.Env(Meta), k: state.Stack(Meta))
  Pending(dep: ir.Reference, env: state.Env(Meta), k: state.Stack(Meta))
}

/// A tool call state and any output printed.
/// Output is held most recent first.
pub type Progress {
  Progress(id: String, output: List(String), call: Call)
}

pub type Calls =
  List(Progress)

pub fn execute_all(
  context: Context,
  tool_calls: List(tool.Call),
) -> #(Context, Calls) {
  list.map_fold(tool_calls, context, execute_single)
}

fn execute_single(ctx: Context, call: tool.Call) -> #(Context, Progress) {
  let tool.Call(id:, function:) = call
  let tool.FunctionCall(name:, arguments:) = function
  case name {
    "run" ->
      case cast_run(arguments) {
        Ok(code) ->
          case parser.all_from_string(code) {
            Ok(source) -> {
              let #(ctx, output, call) =
                source
                |> ir.map_annotation(fn(_) { [] })
                |> expression.execute([])
                |> loop(ctx, [])
              #(ctx, Progress(id:, output:, call:))
            }
            Error(reason) -> #(ctx, failed(id, InvalidCode(reason)))
          }
        Error(reason) -> #(ctx, failed(id, BadArguments(reason)))
      }
    _ -> #(ctx, failed(id, UnknownTool(name)))
  }
}

fn failed(id, call) {
  Progress(id:, output: [], call:)
}

fn cast_run(arguments) {
  let arguments = utils.fields_to_dynamic(arguments)
  let decoder = decode.field("code", decode.string, decode.success)
  decode.run(arguments, decoder)
}

// context can include tasks
// If we don't keep track of errors we'll keep calculating
// prepare and fetch all need to look at relative references
// Or we just type check and lookup
// There's multiple ways to do this, pick one.
// 1. reset failed
// 2. reset pulled
// document/state

fn loop(
  return: Result(state.Value(Meta), state.Debug(Meta)),
  ctx: Context,
  output: List(String),
) -> #(Context, List(String), Call) {
  case return {
    Error(#(break.UndefinedReference(reference), _m, env, k)) -> {
      case reference {
        ir.Content(ref) ->
          case cache.get_module(ctx.cache, ref) {
            Ok(cache.Module(value:, ..)) ->
              loop(expression.resume(value, env, k), ctx, output)
            Error(cache.NotRequested) -> {
              let cache = cache.fetch(ctx.cache, ref)
              let ctx = Context(..ctx, cache:)
              let call = Pending(reference, env, k)
              #(ctx, output, call)
            }
            Error(cache.DependsOn(..)) | Error(cache.Requested) -> {
              #(ctx, output, Pending(reference, env, k))
            }
            Error(cache.Failed(_reason)) -> {
              let message =
                "failed to fetch: " <> ir.reference_to_string(reference)
              #(ctx, output, Aborted(message))
            }
            Error(cache.Invalid(reason)) -> #(ctx, output, Exception(reason))
          }
        ir.Package(package:) -> {
          case cache.package(ctx.cache, package) {
            Ok(cache.Entry(module:, ..)) ->
              case cache.get_module(ctx.cache, module) {
                Ok(cache.Module(value:, ..)) ->
                  loop(expression.resume(value, env, k), ctx, output)
                Error(cache.NotRequested) -> {
                  let cache = cache.fetch(ctx.cache, module)
                  let ctx = Context(..ctx, cache:)
                  let call = Pending(reference, env, k)
                  #(ctx, output, call)
                }
                Error(cache.DependsOn(..)) | Error(cache.Requested) -> {
                  #(ctx, output, Pending(reference, env, k))
                }
                Error(cache.Failed(_reason)) -> {
                  let message =
                    "failed to fetch: " <> ir.reference_to_string(reference)
                  #(ctx, output, Aborted(message))
                }
                Error(cache.Invalid(reason)) -> #(
                  ctx,
                  output,
                  Exception(reason),
                )
              }
            Error(Nil) -> {
              let cache = cache.pull(ctx.cache)
              let ctx = Context(..ctx, cache:)
              let call = Pending(reference, env, k)
              #(ctx, output, call)
            }
          }
        }
        ir.Version(package:, version:) ->
          case cache.unbound_release(ctx.cache, package, version) {
            Ok(module) ->
              case cache.get_module(ctx.cache, module) {
                Ok(cache.Module(value:, ..)) ->
                  loop(expression.resume(value, env, k), ctx, output)
                Error(cache.NotRequested) -> {
                  let cache = cache.fetch(ctx.cache, module)
                  let ctx = Context(..ctx, cache:)
                  let call = Pending(reference, env, k)
                  #(ctx, output, call)
                }
                Error(cache.DependsOn(..)) | Error(cache.Requested) -> {
                  #(ctx, output, Pending(reference, env, k))
                }
                Error(cache.Failed(_reason)) -> {
                  let message =
                    "failed to fetch: " <> ir.reference_to_string(reference)
                  #(ctx, output, Aborted(message))
                }
                Error(cache.Invalid(reason)) -> #(
                  ctx,
                  output,
                  Exception(reason),
                )
              }
            Error(Nil) -> {
              let cache = cache.pull(ctx.cache)
              let ctx = Context(..ctx, cache:)
              let call = Pending(reference, env, k)
              #(ctx, output, call)
            }
          }
        ir.Pinned(release:) ->
          case
            cache.unbound_release(ctx.cache, release.package, release.version)
          {
            Ok(module) if module == release.module ->
              case cache.get_module(ctx.cache, module) {
                Ok(cache.Module(value:, ..)) ->
                  loop(expression.resume(value, env, k), ctx, output)
                Error(cache.NotRequested) -> {
                  let cache = cache.fetch(ctx.cache, module)
                  let ctx = Context(..ctx, cache:)
                  let call = Pending(reference, env, k)
                  #(ctx, output, call)
                }
                Error(cache.DependsOn(..)) | Error(cache.Requested) -> {
                  #(ctx, output, Pending(reference, env, k))
                }
                Error(cache.Failed(_reason)) -> {
                  let message =
                    "failed to fetch: " <> ir.reference_to_string(reference)
                  #(ctx, output, Aborted(message))
                }
                Error(cache.Invalid(reason)) -> #(
                  ctx,
                  output,
                  Exception(reason),
                )
              }
            Ok(_module) -> {
              let message =
                "invalid hash for reference: "
                <> ir.reference_to_string(reference)
              #(ctx, output, Aborted(message))
            }
            Error(Nil) -> {
              let cache = cache.pull(ctx.cache)
              let ctx = Context(..ctx, cache:)
              let call = Pending(reference, env, k)
              #(ctx, output, call)
            }
          }

        ir.Relative(location:) -> {
          let message = "unable to load source from location: " <> location
          #(ctx, output, Aborted(message))
        }
      }
    }
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) -> {
      case browser.cast(label, lift) {
        // Printing belongs to the result the agent reads, not only the browser
        // console. Keeping it here also preserves output across suspension.
        Ok(harness.Print(message)) ->
          loop(expression.resume(v.unit(), env, k), ctx, [message, ..output])
        Ok(effect) -> {
          case browser.extrinsic(effect) {
            browser.Abort(reason) -> #(ctx, output, Aborted(reason))
            browser.Work(system.Done(value)) ->
              loop(expression.resume(value, env, k), ctx, output)
            browser.Work(effect) -> {
              let id = ctx.counter

              let effect = system.map(effect, fn(v) { #(id, v) })
              let effects = [effect, ..ctx.effects]
              let ctx = Context(..ctx, counter: id + 1, effects:)
              #(ctx, output, Handling(id, env, k))
            }
            browser.Spotless(..) -> #(
              ctx,
              output,
              Aborted("Spotless integration not supported in harness"),
            )
          }
        }
        Error(reason) -> #(ctx, output, Exception(reason))
      }
    }
    Error(#(reason, _, _, _)) -> #(ctx, output, Exception(reason))
    Ok(value) -> #(ctx, output, Successful(value))
  }
}

fn is_running(call: Call) {
  case call {
    UnknownTool(..)
    | BadArguments(..)
    | InvalidCode(..)
    | Successful(..)
    | Exception(..)
    | Aborted(..) -> False
    Handling(..) | Pending(..) -> True
  }
}

pub fn any_running(tool_calls: Calls) {
  list.any(tool_calls, fn(progress: Progress) { is_running(progress.call) })
}

pub fn all_returns(calls) {
  do_all_returns(calls, [])
}

fn do_all_returns(calls: Calls, acc) {
  case calls {
    [] -> Ok(list.reverse(acc))
    [Progress(id:, output:, call:), ..calls] -> {
      let message = case call {
        UnknownTool(name:) -> Ok("unknown tool: " <> name)
        BadArguments(reasons) -> Ok(string.inspect(reasons))
        InvalidCode(reason) -> Ok(debug.describe(reason))
        Successful(value) -> Ok(simple_debug.inspect(value))
        Exception(reason) -> Ok(simple_debug.describe(reason))
        Aborted(reason) -> Ok(reason)
        Handling(..) | Pending(..) -> Error(Nil)
      }
      case message {
        Ok(text) -> {
          let message =
            chat.ToolResultMessage(
              tool_call_id: id,
              text: report(output, text),
              images: [],
            )
          do_all_returns(calls, [message, ..acc])
        }
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

/// Return everything printed before the final result of the tool call.
pub fn report(output: List(String), result: String) -> String {
  case list.reverse(output) {
    [] -> result
    printed -> "Output:\n" <> string.concat(printed) <> "\nResult:\n" <> result
  }
}

pub fn restart(ctx: Context, progress: Progress) -> #(Context, Progress) {
  let Progress(id:, output:, call:) = progress
  case call {
    Pending(dep:, env:, k:) -> {
      let reason = break.UndefinedReference(dep)
      let #(ctx, output, call) = loop(Error(#(reason, [], env, k)), ctx, output)
      #(ctx, Progress(id:, output:, call:))
    }
    _ -> #(ctx, progress)
  }
}

pub fn effect_handled(
  ctx: Context,
  calls: Calls,
  id: Int,
  value: state.Value(Meta),
) -> #(Context, Calls) {
  list.map_fold(calls, ctx, fn(ctx, call) { apply_effect(ctx, call, id, value) })
}

fn apply_effect(
  ctx: Context,
  progress: Progress,
  finished_id: Int,
  value: state.Value(Meta),
) {
  let Progress(id:, output:, call:) = progress
  case call {
    Handling(task_id:, env:, k:) if task_id == finished_id -> {
      let #(ctx, output, call) =
        loop(expression.resume(value, env, k), ctx, output)
      #(ctx, Progress(id:, output:, call:))
    }
    _ -> #(ctx, progress)
  }
}
