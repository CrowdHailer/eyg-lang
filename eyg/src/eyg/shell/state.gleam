import drafting/view/utilities
import eyg/analysis/inference/levels_j/contextual as j
import eyg/runtime/break
import eyg/runtime/interpreter/block as r
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
import eyg/shell/buffer as b
import eyg/shell/situation.{type Situation}
import eyg/sync/browser
import eyg/sync/sync
import eygir/annotated as a
import eygir/expression as e
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import harness/fetch
import harness/impl/browser/file/list as fs_list
import harness/impl/browser/file/read as fs_read
import harness/impl/browser/geolocation as geo
import harness/impl/browser/now
import harness/impl/browser/visit
import harness/impl/spotless/gmail/list_messages as gmail_list_messages
import harness/impl/spotless/gmail/send as gmail_send
import harness/impl/spotless/google
import harness/impl/spotless/netlify
import harness/impl/spotless/netlify/deploy_site as netlify_deploy_site
import harness/impl/spotless/netlify/list_sites as netlify_list_sites
import harness/impl/spotless/vimeo
import harness/impl/spotless/vimeo/my_videos as vimeo_my_videos
import harness/stdlib
import lustre/effect
import morph/analysis
import morph/editable
import morph/projection as p
import plinth/browser/clipboard
import snag.{type Snag}

type Path =
  List(Int)

type Value =
  v.Value(Path, #(List(#(istate.Kontinue(Path), Path)), istate.Env(Path)))

type Scope =
  #(List(#(String, Value)), j.Env)

pub type Suspended {
  Handling(
    label: String,
    lift: Value,
    env: istate.Env(Path),
    k: istate.Stack(Path),
  )
  Failed(istate.Debug(Path))
}

pub type Run {
  Run(suspended: Suspended, effects: List(#(String, #(Value, Value))))
}

pub type Shell {
  Shell(
    situation: Situation,
    cache: sync.Sync,
    previous: List(#(Option(Value), editable.Expression)),
    scope: Option(Scope),
    buffer: b.Buffer,
    runner: Option(Run),
  )
}

const scratch_ref = "heae72a60"

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  let #(cache, tasks) = sync.fetch_missing(cache, [scratch_ref])

  let situation = situation.init()

  let state = Shell(situation, cache, [], None, b.empty(), None)

  #(state, effect.from(browser.do_sync(tasks, Synced)))
}

fn execute(exp, env, values) {
  let h = dict.new()
  let env =
    istate.Env(
      ..stdlib.env()
      |> dynamic.from()
      |> dynamicx.unsafe_coerce(),
      references: values,
      scope: env,
    )
  r.execute(exp, env, h)
}

pub type ExecutorMessage {
  Reply(Value)
}

pub type Message {
  Synced(reference: String, value: Result(e.Expression, Snag))
  Selected(p.Projection)
  Buffer(b.Message)
  Executor(ExecutorMessage)
  Interrupt
}

// TODO this is the spotless section
fn effects() {
  [
    #(now.l, #(now.lift, now.reply, now.blocking)),
    #(fetch.l, #(fetch.lift(), fetch.lower(), fetch.blocking)),
    #(fs_list.l, #(fs_list.lift, fs_list.lower(), fs_list.blocking)),
    #(fs_read.l, #(fs_read.lift, fs_read.lower(), fs_read.blocking)),
    #(geo.l, #(geo.lift, geo.lower(), geo.blocking)),
    #(google.l, #(google.lift, google.reply, google.blocking(google.local, _))),
    #(
      gmail_send.l,
      #(gmail_send.lift(), gmail_send.reply(), gmail_send.blocking(
        google.local,
        _,
      )),
    ),
    #(
      gmail_list_messages.l,
      #(
        gmail_list_messages.lift(),
        gmail_list_messages.reply(),
        gmail_list_messages.blocking(google.local, _),
      ),
    ),
    #(
      netlify.l,
      #(netlify.lift, netlify.reply, netlify.blocking(netlify.local, _)),
    ),
    #(
      vimeo_my_videos.l,
      #(vimeo_my_videos.lift, vimeo_my_videos.reply(), vimeo_my_videos.blocking(
        vimeo.local,
        _,
      )),
    ),
    #(
      netlify_list_sites.l,
      #(
        netlify_list_sites.lift,
        netlify_list_sites.reply(),
        netlify_list_sites.blocking(netlify.local, _),
      ),
    ),
    #(
      netlify_deploy_site.l,
      #(
        netlify_deploy_site.lift(),
        netlify_deploy_site.reply(),
        netlify_deploy_site.blocking(netlify.local, _),
      ),
    ),
    #(visit.l, #(visit.lift, visit.reply(), visit.blocking)),
  ]
}

fn effect_types() {
  listx.value_map(effects(), fn(details) { #(details.0, details.1) })
}

pub fn update(state, message) {
  let effects = effect_types()

  case message {
    Synced(ref, result) -> {
      let Shell(cache: cache, scope: scope, ..) = state
      let cache = sync.task_finish(cache, ref, result)
      let #(cache, tasks) = sync.fetch_missing(cache, [ref])

      let scope = case sync.missing(cache, [scratch_ref]) {
        [] -> {
          let assert Ok(sync.Computed(expression: exp, ..)) =
            sync.value(cache, scratch_ref)
          let scratch = exp |> a.add_annotation([])
          let assert Ok(#(_value, env)) =
            execute(scratch, [], sync.values(cache))

          let proj = p.focus_at(editable.from_expression(exp), [])

          let context =
            analysis.Context(
              // bindings are empty as long as everything is properly poly
              bindings: dict.new(),
              scope: [],
              references: sync.types(cache),
              builtins: j.builtins(),
            )
          let tenv = b.final_scope(proj, context)

          Some(#(env, tenv))
        }
        _ -> scope
      }

      let state = Shell(..state, scope: scope, cache: cache)
      #(state, effect.from(browser.do_sync(tasks, Synced)))
    }
    Selected(projection) -> {
      let buffer = b.from(projection)
      let state = Shell(..state, buffer: buffer)
      // might need to load up effects
      #(state, effect.none())
    }
    Buffer(message) -> {
      let Shell(cache: cache, scope: scope, runner: run, buffer: buffer, ..) =
        state
      case run {
        Some(Run(Handling(_, _, _, _), _)) -> #(state, effect.none())
        None | Some(Run(Failed(_), _)) -> {
          let context =
            analysis.Context(
              // bindings are empty as long as everything is properly poly
              bindings: dict.new(),
              scope: case scope {
                Some(#(_env, tenv)) -> tenv
                None -> []
              },
              references: sync.types(cache),
              builtins: j.builtins(),
            )
          let buffer = b.update(buffer, message, context, effects)
          utilities.update_focus()
          let references = b.references(buffer)

          let #(source, mode) = buffer
          case mode, p.blank(source), sync.missing(cache, references), scope {
            b.Command(Some(b.NoKeyBinding("Enter"))), False, [], Some(scope) -> {
              let #(env, _tenv) = scope
              let buffer = #(source, b.Command(None))
              let expression = editable.to_annotated(p.rebuild(source), [])
              execute(expression, env, sync.values(cache))
              |> handle_execution([], scope, state)
            }
            b.Command(Some(b.NoKeyBinding("Enter"))), False, _, _ -> {
              let buffer = #(source, b.Command(Some(b.ActionFailed("run"))))
              #(Shell(..state, buffer: buffer), effect.none())
            }
            b.Command(Some(b.ActionFailed("move up"))), True, [], _ -> {
              case state.previous {
                [] -> #(state, effect.none())
                [#(_value, expression), ..] -> {
                  let buffer = b.from(p.focus_at(expression, []))
                  let state = Shell(..state, buffer: buffer)
                  #(state, effect.none())
                }
              }
            }
            b.Command(Some(b.NoKeyBinding("Q"))), _, _, _ -> {
              clipboard.write_text(b.all_escaped(buffer))
              // can send a message saying copied
              |> promise.map(io.debug)
              let buffer = #(source, b.Command(None))
              #(Shell(..state, buffer: buffer), effect.none())
            }
            _, _, _missing, _ -> {
              let #(cache, tasks) = sync.fetch_missing(cache, references)
              #(
                Shell(..state, cache: cache, buffer: buffer, runner: None),
                effect.from(browser.do_sync(tasks, Synced)),
              )
            }
          }
        }
      }
    }
    Executor(Reply(reply)) -> {
      let Shell(scope: scope, runner: run, ..) = state
      let assert Some(scope) = scope
      let assert Some(Run(Handling(label, lift, env, k), effects)) = run
      let effects = [#(label, #(lift, reply)), ..effects]

      r.resume(reply, env, k)
      |> handle_execution(effects, scope, state)
    }
    Interrupt -> {
      let state = Shell(..state, runner: None)
      #(state, effect.none())
    }
  }
}

fn handle_execution(result, effects, scope, state) {
  let Shell(buffer: buffer, previous: previous, cache: cache, ..) = state
  let #(source, _mode) = buffer
  let #(_env, tenv) = scope
  case result {
    Ok(#(value, env)) -> {
      let previous = [#(value, p.rebuild(source)), ..previous]
      let context =
        analysis.Context(
          // bindings are empty as long as everything is properly poly
          bindings: dict.new(),
          scope: tenv,
          references: sync.types(cache),
          builtins: j.builtins(),
        )
      let tenv = b.final_scope(source, context)
      let scope = Some(#(env, tenv))
      let run = None
      let buffer = b.empty()
      let state =
        Shell(
          ..state,
          buffer: buffer,
          runner: run,
          scope: scope,
          previous: previous,
        )
      #(state, effect.none())
    }
    Error(debug) -> {
      let #(suspend, effect) = handle_extrinsic_effects(debug)
      let run = Some(Run(suspend, effects))
      let state = Shell(..state, runner: run)
      #(state, effect)
    }
  }
}

pub fn handle_extrinsic_effects(debug) {
  let #(reason, meta, env, k) = debug
  case reason {
    break.UnhandledEffect(label, lift) ->
      case list.key_find(effects(), label) {
        Ok(#(_lift, _reply, handle)) ->
          case handle(lift) {
            Error(reason) -> #(Failed(#(reason, meta, env, k)), effect.none())
            Ok(p) -> #(
              Handling(label, lift, env, k),
              effect.from(fn(d) {
                promise.map(p, fn(v) { d(Executor(Reply(v))) })
                Nil
              }),
            )
          }
        _ -> #(Failed(debug), effect.none())
      }
    _ -> #(Failed(debug), effect.none())
  }
}
