import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug as analysis_debug
import eyg/analysis/type_/binding/error
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/ir/utils.{push_new} as _
import eyg/parser
import eyg/parser/debug
import eyg/parser/parser.{type Reason} as _
import gleam/dynamic/decode
import gleam/list
import gleam/string
import multiformats/cid/v1
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import pal/platform/browser
import pal/system
import touch_grass/harness/browser as harness
import touch_grass/interface

pub type Context {
  Context(
    cache: cache.Cache(Meta),
    counter: Int,
    effects: List(system.Effect(#(Int, state.Value(Meta)))),
    context: cache.Module(Meta),
  )
}

pub type Meta =
  List(Int)

/// The running state of a given tool call
pub type Call {
  UnknownTool(name: String)
  BadArguments(List(decode.DecodeError))
  InvalidCode(Reason)
  Pulling(ir.Node(Meta))
  Fetching(cids: List(v1.Cid), source: ir.Node(Meta))
  Successful(state.Value(Meta))
  Errored(List(#(Meta, error.Reason)))
  Exception(state.Reason(Meta))
  Aborted(String)
  Handling(task_id: Int, env: state.Env(Meta), k: state.Stack(Meta))
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
              let source = ir.map_annotation(source, fn(_) { [] })
              case check_single(source, ctx.cache, ctx.context) {
                [] -> {
                  let #(ctx, output, call) =
                    source
                    |> execute(ctx.context)
                    |> loop(ctx, [])
                  #(ctx, Progress(id:, output:, call:))
                }
                errors -> {
                  let references = missing_references(errors)
                  case requires_pull(references, ctx.cache) {
                    True -> {
                      let cache = cache.pull(ctx.cache)
                      let ctx = Context(..ctx, cache:)
                      #(ctx, failed(id, Pulling(source)))
                    }
                    False -> {
                      case to_fetch(references, ctx.cache, []) {
                        [] -> #(ctx, failed(id, Errored(errors)))
                        needed -> {
                          let cache = cache.fetch_all(ctx.cache, needed)
                          let ctx = Context(..ctx, cache:)
                          #(ctx, failed(id, Fetching(needed, source)))
                        }
                      }
                    }
                  }
                }
              }
            }
            Error(reason) -> #(ctx, failed(id, InvalidCode(reason)))
          }
        Error(reason) -> #(ctx, failed(id, BadArguments(reason)))
      }
    _ -> #(ctx, failed(id, UnknownTool(name)))
  }
}

fn check_single(
  source: #(ir.Expression(a), a),
  cache: cache.Cache(b),
  context: cache.Module(_),
) -> List(#(a, error.Reason)) {
  let analysis =
    infer.pure()
    |> with_scope([#("context", context.type_)])
    |> infer.with_effects(interface.types(harness.effects()))
    |> infer.check(source)
    |> cache.infer_sync(cache)
  infer.all_errors(analysis)
}

// TODO move to infer module
fn with_scope(
  context: infer.Context,
  scope: List(#(String, binding.Poly)),
) -> infer.Context {
  let infer.Context(env:, ..) = context
  infer.Context(..context, env: list.append(scope, env))
}

pub fn missing_references(errors) {
  list.filter_map(errors, fn(error) {
    let #(_, error) = error
    case error {
      error.MissingReference(reference:) -> Ok(reference)
      _ -> Error(Nil)
    }
  })
}

fn requires_pull(refs, cache) {
  case refs {
    [] -> False
    [reference, ..rest] ->
      case reference {
        ir.Content(..) | ir.Relative(..) -> requires_pull(rest, cache)
        ir.Package(package:) ->
          case cache.package(cache, package) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
        ir.Version(package:, version:) ->
          case cache.unbound_release(cache, package, version) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
        ir.Pinned(release: ir.Release(package:, version:, module: _)) ->
          case cache.unbound_release(cache, package, version) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
      }
  }
}

pub fn to_fetch(
  refs: List(ir.Reference),
  cache: cache.Cache(a),
  acc: List(v1.Cid),
) -> List(v1.Cid) {
  case refs {
    [] -> acc
    [reference, ..rest] -> {
      let acc = case reference {
        ir.Content(cid:) -> push_new(acc, cid)
        ir.Package(package:) ->
          case cache.package(cache, package) {
            Ok(cache.Entry(module:, ..)) -> push_new(acc, module)
            Error(_) -> acc
          }
        ir.Version(package:, version:) ->
          case cache.unbound_release(cache, package, version) {
            Ok(cid) -> push_new(acc, cid)
            Error(_) -> acc
          }
        // Only the release log can make a pin right, so there is nothing to
        // gain from fetching a module it does not name for that release.
        ir.Pinned(release: ir.Release(package:, version:, module:)) ->
          case cache.unbound_release(cache, package, version) {
            Ok(cid) if cid == module -> push_new(acc, module)
            _ -> acc
          }
        ir.Relative(..) -> acc
      }
      to_fetch(rest, cache, acc)
    }
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
    Error(#(break.UndefinedReference(reference) as break, _m, env, k)) -> {
      case reference {
        ir.Relative(location:) -> {
          let message = "unable to load source from location: " <> location
          #(ctx, output, Aborted(message))
        }
        _ ->
          case cache.get_reference(ctx.cache, reference) {
            Ok(cache.Module(value:, ..)) ->
              loop(expression.resume(value, env, k), ctx, output)
            Error(Nil) -> #(ctx, output, Exception(break))
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
    | Errored(..)
    | Exception(..)
    | Aborted(..) -> False
    Handling(..) | Pulling(..) | Fetching(..) -> True
  }
}

pub fn any_running(tool_calls: Calls) {
  list.any(tool_calls, fn(progress: Progress) { is_running(progress.call) })
}

pub fn all_returns(calls) {
  do_all_returns(calls, [])
}

fn do_all_returns(
  calls: Calls,
  acc: List(chat.Message(a)),
) -> Result(List(chat.Message(a)), Nil) {
  case calls {
    [] -> Ok(list.reverse(acc))
    [Progress(id:, output:, call:), ..calls] -> {
      let message = case call {
        UnknownTool(name:) -> Ok("unknown tool: " <> name)
        BadArguments(reasons) -> Ok(string.inspect(reasons))
        InvalidCode(reason) -> Ok(debug.describe(reason))
        Successful(value) -> Ok(simple_debug.inspect(value))
        Errored(errors) -> {
          list.map(errors, fn(error) { analysis_debug.reason(error.1) })
          |> string.join("\n")
          |> Ok()
        }
        Exception(reason) -> Ok(simple_debug.describe(reason))
        Aborted(reason) -> Ok(reason)
        Handling(..) | Pulling(..) | Fetching(..) -> Error(Nil)
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

pub fn pulled(ctx: Context, progress: Progress) -> #(Context, Progress) {
  let Progress(id:, output:, call:) = progress

  case call {
    Pulling(source) -> {
      // TODO move to cache.infer_sync that will gather need to pull and to fetch references
      case check_single(source, ctx.cache, ctx.context) {
        [] -> {
          let #(ctx, output, call) =
            source
            |> execute(ctx.context)
            // output should always be empty going into this loop.
            // Maybe output should move into a running state of call
            |> loop(ctx, output)
          #(ctx, Progress(id:, output:, call:))
        }
        errors -> {
          // Don't check for needs pull here as we've aready done that.
          let references = missing_references(errors)
          case to_fetch(references, ctx.cache, []) {
            [] -> #(ctx, failed(id, Errored(errors)))
            needed -> {
              let cache = cache.fetch_all(ctx.cache, needed)
              let ctx = Context(..ctx, cache:)
              #(ctx, failed(id, Fetching(needed, source)))
            }
          }
        }
      }
    }
    _ -> #(ctx, progress)
  }
}

fn execute(source: ir.Node(Meta), context: cache.Module(Meta)) {
  expression.execute(source, [#("context", context.value)])
}

pub fn check_fetching(
  ctx: Context,
  progress: Progress,
) -> #(Context, Progress) {
  let Progress(id:, output:, call:) = progress
  case call {
    Fetching(cids:, source:) -> {
      let cids = list.filter(cids, still_fetching(_, ctx.cache))
      case cids {
        [] ->
          case check_single(source, ctx.cache, ctx.context) {
            [] -> {
              let #(ctx, output, call) =
                source
                |> execute(ctx.context)
                // output should always be empty going into this loop.
                // Maybe output should move into a running state of call
                |> loop(ctx, output)
              #(ctx, Progress(id:, output:, call:))
            }
            errors -> #(ctx, failed(id, Errored(errors)))
          }
        _ -> #(ctx, failed(id, Fetching(cids, source)))
      }
    }
    _ -> #(ctx, progress)
  }
}

// TODO move this to cache
pub fn still_fetching(cid, cache) {
  case cache.get_module(cache, cid) {
    Ok(_) -> False
    // Not requested is the state given by fetch and before flush.
    // It means not requested from the network not never requested by the user.
    Error(cache.NotRequested)
    | Error(cache.Requested(..))
    | Error(cache.DependsOn(..)) -> True

    Error(cache.Failed(_)) | Error(cache.Invalid(_)) -> False
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
