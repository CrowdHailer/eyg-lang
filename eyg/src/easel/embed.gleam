import gleam/bit_array
import gleam/io
import gleam/int
import gleam/list
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/regex
import gleam/result
import gleam/string
import gleam/stringx
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/fetch
import eygir/annotated as a
import eygir/expression as e
import eygir/encode
import eygir/decode
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eyg/runtime/break
import harness/stdlib
import harness/effect
import eyg/analysis/jm/tree
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/env as tenv
import easel/print
import easel/expression/zipper
import atelier/view/type_
import gleam/javascript
import gleam/javascript/array
import gleam/javascript/promise
import plinth/browser/file_system
import plinth/browser/file
import plinth/browser/selection
import plinth/browser/range
import old_plinth/browser/document
import platforms/browser
import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/isomorphic as tj

// TODO remove last run information when moving cursor
// TODO have a program in the editor at startup
// TODO print large arrays on multiple lines
// TODO multi line string can collapse with ... outside quote marks
// Not a full app
// Widget is another name element/panel
// Embed if I have a separate app file
// TODO svelte memoisation of print OR collapse nodes
// TODO auto infer if using the same state, maybe part of history API
// TODO hash/name for restart/resumption in client (qwikloader)
// TODO easil document.query selector general restart
// TODO document hash watch registering, maybe not needed with global handlers
// debounce, frp in use
// Do a print function that goes to HTML from tree directly
// bg highlight selection or error as in aterlier
// debounce move to opening
// Can a match be dynamic I think no
// press a increases selection but uses browser selection
// ardunio/structured text auto reload OR gateway for OPCUA using erlang

pub type Mode {
  Command(warning: String)
  Insert
}

pub type Path =
  List(Int)

pub type Edit =
  #(e.Expression, Path, Bool)

pub type History =
  #(List(Edit), List(Edit))

pub type Embed {
  Embed(
    mode: Mode,
    yanked: Option(e.Expression),
    env: #(state.Env(Nil), t.Substitutions, Int, tenv.Env),
    source: e.Expression,
    history: History,
    auto_infer: Bool,
    inferred: Option(tree.State),
    // not actually used but I think useful for clearing run value
    returned: Option(state.Return(Nil)),
    rendered: #(List(print.Rendered), dict.Dict(String, Int)),
    focus: Option(List(Int)),
  )
}

// infer continuation
fn do_infer(source, cache) {
  let #(_env, sub, next, tenv) = cache
  tree.infer_env(source, t.Var(-10), t.Var(-11), tenv, sub, next).0
}

fn nearest_click_handler(event) {
  let target = document.target(event)
  case document.closest(target, "[data-click]") {
    Ok(element) -> {
      // Because the closest element is chosen to have data-click this get must return ok
      let assert Ok(handle) = document.dataset_get(element, "click")
      Ok(handle)
    }
    Error(Nil) -> Error(Nil)
  }
}

fn load_source() {
  use file_handles <- promise.try_await(file_system.show_open_file_picker())
  let assert [file_handle] = array.to_list(file_handles)
  use file <- promise.try_await(file_system.get_file(file_handle))
  use text <- promise.map(file.text(file))
  let assert Ok(source) = decode.from_json(text)
  Ok(source)
}

// This is used in the editor when loading from file
pub fn handle_click(root, event) {
  case nearest_click_handler(event) {
    Ok("load") -> {
      promise.map_try(load_source(), fn(source) {
        // let #(#(sub, next, _types), envs) =
        //   tree.infer(source, t.Var(-1), t.Var(-2))
        // let #(Ok(v.Closure(_, source, _e2, rev)), env) =
        //   r.resumable(source, stdlib.env(), None)
        // let assert Ok(tenv) = dict.get(envs, rev)
        io.debug("inferring")
        j.infer(source, tj.Empty, 0, j.new_state())
        io.debug("inferred")

        let env = stdlib.env()
        let sub = dict.new()
        let next = 0
        let tenv = dict.new()
        let cache = #(env, sub, next, tenv)
        let inferred = None
        //   Some(tree.infer_env(source, t.Var(-3), t.Var(-4), tenv, sub, next).0)

        let rendered = print.print(source, Some([]), False, inferred)
        let assert Ok(start) = dict.get(rendered.1, print.path_to_string([]))

        let state =
          Embed(
            mode: Command(""),
            yanked: None,
            env: cache,
            source: source,
            history: #([], []),
            auto_infer: False,
            inferred: inferred,
            returned: None,
            rendered: rendered,
            focus: None,
          )
        start_easel_at(root, start, state)
        Ok(Nil)
      })

      Nil
    }
    Ok(_) -> {
      io.debug(#("unknown click", handle))
      Nil
    }
    Error(Nil) -> Nil
  }
}

pub fn start_easel_at(root, start, state) {
  render_page(root, start, state)
  let ref = javascript.make_reference(state)
  case document.query_selector(root, "pre") {
    Ok(pre) -> {
      document.add_event_listener(pre, "blur", fn(_) {
        io.debug("blurred")
        javascript.update_reference(ref, fn(state) {
          // updating the contenteditable node messes with cursor placing
          let state = blur(state)
          document.set_html(pre, html(state))
          let pallet_el = document.next_element_sibling(pre)
          document.set_html(pallet_el, pallet(state))
          state
        })

        Nil
      })
      Nil
    }
    _ -> {
      io.debug("expected a pre to be available")
      Nil
    }
  }
  document.add_event_listener(
    // event can have phantom type which is the internal event type
    document.document(),
    "selectionchange",
    fn(_event) {
      let _ = {
        use selection <- result.then(selection.get_selection())
        use range <- result.then(selection.get_range_at(selection, 0))
        let start = start_index(range)
        let end = end_index(range)
        javascript.update_reference(ref, fn(state) {
          let state = update_selection(state, start, end)
          let rendered =
            print.print(
              state.source,
              state.focus,
              state.auto_infer,
              state.inferred,
            )
          case rendered == state.rendered {
            True -> {
              io.debug("no focus change")
              state
            }
            False -> {
              let assert Ok(start) =
                dict.get(
                  rendered.1,
                  print.path_to_string(option.unwrap(state.focus, [])),
                )

              let state = Embed(..state, rendered: rendered)
              render_page(root, start, state)
              state
            }
          }
        })

        Ok(Nil)
      }

      Nil
    },
  )
  document.add_event_listener(root, "beforeinput", fn(event) {
    document.prevent_default(event)
    handle_input(
      event,
      fn(data, start, end) {
        javascript.update_reference(ref, fn(state) {
          // pass in updeate ref
          let #(state, start, actions) = insert_text(state, data, start, end)
          render_page(root, start, state)
          io.debug(actions)
          list.map(actions, fn(updater) {
            promise.map(updater, fn(updater) {
              javascript.update_reference(ref, fn(state) {
                let state = updater(state)
                io.debug("lots of update")
                render_page(root, start, state)
                state
              })
            })
          })
          state
        })
        Nil
      },
      fn(start) {
        javascript.update_reference(ref, fn(state) {
          let #(state, start) = insert_paragraph(start, state)
          render_page(root, start, state)
          state
        })
        // todo pragraph
        io.debug(#(start))
        Nil
      },
    )
  })
  document.add_event_listener(root, "keydown", fn(event) {
    case
      case document.key(event) {
        "Escape" -> {
          javascript.update_reference(ref, fn(s) {
            let s = escape(s)
            case document.query_selector(root, "pre + *") {
              Ok(pallet_el) -> document.set_html(pallet_el, pallet(s))
              Error(Nil) -> Nil
            }
            s
          })
          Ok(Nil)
        }
        _ -> Error(Nil)
      }
    {
      Ok(Nil) -> document.prevent_default(event)
      Error(Nil) -> Nil
    }
  })
}

pub fn fullscreen(root) {
  document.add_event_listener(root, "click", handle_click(root, _))

  document.set_html(
    root,
    "<div  class=\"cover expand vstack pointer\"><div class=\"cover text-center cursor-pointer\" data-click=\"load\">click to load</div><div class=\"cover text-center cursor-pointer hidden\" data-click=\"new\">start new</div></div>",
  )
  Nil
}

// These iterate through spans so needs some thought to change
@external(javascript, "../easel_ffi.js", "startIndex")
fn start_index(a: range.Range) -> Int

@external(javascript, "../easel_ffi.js", "endIndex")
fn end_index(a: range.Range) -> Int

fn render_page(root, start, state) {
  case document.query_selector(root, "pre") {
    Ok(pre) -> {
      // updating the contenteditable node messes with cursor placing
      document.set_html(pre, html(state))
      let pallet_el = document.next_element_sibling(pre)
      document.set_html(pallet_el, pallet(state))
    }

    Error(Nil) -> {
      let content =
        string.concat([
          "<pre class=\"expand overflow-auto outline-none w-full my-1 mx-4\" contenteditable spellcheck=\"false\">",
          html(state),
          "</pre>",
          "<div class=\"w-full bg-purple-1 px-4 font-mono font-bold\">",
          pallet(state),
          "</div>",
        ])
      document.set_html(root, content)
    }
  }

  let assert Ok(pre) = document.query_selector(root, "pre")
  place_cursor(pre, start)
}

@external(javascript, "../easel_ffi.js", "handleInput")
pub fn handle_input(
  a: document.Event,
  insert_text insert_text: fn(String, Int, Int) -> Nil,
  insert_paragraph insert_paragraph: fn(Int) -> Nil,
) -> Nil

// relies on a flat list of spans
@external(javascript, "../easel_ffi.js", "placeCursor")
pub fn place_cursor(a: document.Element, b: Int) -> Nil

pub fn snippet(root) {
  // TODO remove init and resume because they need to call out to the server
  // TODO make a components lib in webside
  io.debug("start snippet")
  case document.query_selector(root, "script[type=\"application/eygir\"]") {
    Ok(script) -> {
      let assert Ok(source) = decode.from_json(document.inner_text(script))
      // always infer at the start

      let #(#(sub, next, _types), envs) =
        tree.infer(source, t.Var(-1), t.Var(-2))
      let assert Ok(v.Closure(_, source, _e2)) =
        execute(source, stdlib.env(), dict.new())
      let assert Ok(tenv) = dict.get(envs, [])
      let source = a.drop_annotation(source)
      let inferred =
        Some(tree.infer_env(source, t.Var(-3), t.Var(-4), tenv, sub, next).0)

      let rendered = print.print(source, Some([]), False, inferred)
      let assert Ok(start) = dict.get(rendered.1, print.path_to_string([]))

      let state =
        Embed(
          mode: Command(""),
          yanked: None,
          env: #(todo("env not needed"), sub, next, tenv),
          source: source,
          history: #([], []),
          auto_infer: True,
          inferred: inferred,
          returned: None,
          rendered: rendered,
          focus: None,
        )
      document.set_html(root, "")
      start_easel_at(root, start, state)
      Nil
    }
    Error(Nil) -> {
      io.debug("nothing found")
      Nil
    }
  }
}

fn execute(source, env, handlers) {
  let source = a.add_annotation(source, Nil)
  r.execute(source, env, handlers)
}

// remove once we use snippet everywhere
pub fn init(json) {
  io.debug("init easil")
  let assert Ok(source) = decode.decoder(json)
  let env = stdlib.env()
  let #(#(sub, next, _types), envs) = tree.infer(source, t.Var(-1), t.Var(-2))

  let #(env, source, sub, next, tenv) = case
    execute(source, stdlib.env(), dict.new())
  {
    Ok(v.Closure(_, source, env)) -> {
      let tenv = case dict.get(envs, []) {
        Ok(tenv) -> tenv
        Error(Nil) -> {
          io.debug(#("no env foud at rev", []))
          dict.new()
        }
      }

      #(stdlib.env(), a.drop_annotation(source), sub, next, tenv)
    }
    _ -> #(env, source, dict.new(), 0, dict.new())
  }
  let cache = #(env, sub, next, tenv)
  // can keep inferred in history
  let inferred = do_infer(source, cache)
  let rendered = print.print(source, None, True, Some(inferred))
  Embed(
    mode: Command(""),
    yanked: None,
    env: cache,
    source: source,
    history: #([], []),
    auto_infer: True,
    inferred: Some(inferred),
    returned: None,
    rendered: rendered,
    focus: None,
  )
}

// can take position
fn is_var(value) {
  let assert Ok(re) = regex.from_string("^[a-z_]$")
  case value {
    "" -> True
    _ -> regex.check(re, value)
  }
}

fn is_tag(value) {
  let assert Ok(re) = regex.from_string("^[A-Za-z]$")
  case value {
    "" -> True
    _ -> regex.check(re, value)
  }
}

fn is_num(value) {
  result.is_ok(int.parse(value))
}

pub fn insert_text(state: Embed, data, start, end) {
  let rendered = state.rendered.0
  case state.mode {
    Command(_) -> {
      case data {
        " " -> {
          case state.inferred {
            Some(_) -> {
              let #(message, actions) = run(state)
              let state = Embed(..state, mode: Command(message))
              #(state, start, actions)
            }
            None -> {
              let inferred = do_infer(state.source, state.env)
              let state =
                Embed(..state, mode: Command(""), inferred: Some(inferred))
              #(state, start, [])
            }
          }
        }
        // Putting in state locked can work with using an series of promises to compose actios
        "Q" -> {
          promise.await(file_system.show_save_file_picker(), fn(result) {
            case
              result
              |> io.debug
            {
              Ok(file_handle) -> {
                use writable <- promise.try_await(file_system.create_writable(
                  file_handle,
                ))
                io.debug(writable)
                let content =
                  bit_array.from_string(encode.to_json(state.source))
                // let blob = blob.new(content, "application/json")
                use _ <- promise.await(file_system.write(writable, content))
                use _ <- promise.await(file_system.close(writable))
                promise.resolve(Ok(Nil))
              }
              Error(reason) -> {
                io.debug(#("no file  to save selected", reason))
                promise.resolve(Ok(Nil))
              }
            }
          })

          #(state, start, [])
        }
        "q" -> {
          let dump = encode.to_json(state.source)
          // io.print(dump)
          let request =
            request.new()
            |> request.set_method(http.Post)
            |> request.set_scheme(http.Http)
            |> request.set_host("localhost:8080")
            |> request.set_path("/save")
            |> request.set_body(dump)
          promise.map(fetch.send(request), fn(response) {
            case response {
              Ok(response.Response(status: 200, ..)) -> {
                Nil
              }
              _ -> {
                io.debug("failed to save")
                Nil
              }
            }
          })
          #(state, start, [])
        }

        "w" -> call_with(state, start, end)
        "e" -> assign_to(state, start, end)
        "E" -> assign_before(state, start, end)
        "r" -> extend(state, start, end)
        "R" -> extender(state, start, end)
        "t" -> tag(state, start, end)
        "y" -> copy(state, start, end)
        "Y" -> paste(state, start, end)
        "i" -> #(Embed(..state, mode: Insert), start, [])
        "[" | "x" -> list_element(state, start, end)
        "," -> extend_list(state, start, end)
        "." -> spread_list(state, start, end)
        "o" -> overwrite(state, start, end)
        "p" -> perform(state, start, end)
        "s" -> string(state, start, end)
        "d" -> delete(state, start, end)
        "f" -> insert_function(state, start, end)
        "g" -> select(state, start, end)
        "h" -> handle(state, start, end)
        "H" -> shallow(state, start, end)
        "j" -> builtin(state, start, end)
        "z" -> undo(state, start)
        "Z" -> redo(state, start)
        // "x" -> ALREADY USED as list
        "c" -> call(state, start, end)
        "b" -> binary(state, start, end)
        "n" -> number(state, start, end)
        "m" -> match(state, start, end)
        "M" -> nocases(state, start, end)

        // TODO reuse history and inference components
        // Reuse lookup of variables
        // Don't worry about big code blocks at this point, I can use my silly backwards editor
        // hardcode stdlib at the top
        // run needs to be added
        // embed can have a minimum height then safe to show logs when running
        // terminal at the bottom can have a line buffer for reading input
        key -> {
          let mode = Command(string.append("no command for key ", key))
          #(Embed(..state, mode: mode), start, [])
        }
      }
    }
    Insert -> {
      let assert Ok(#(_ch, path, cut_start, _style, _err)) =
        list.at(rendered, start)
      let assert Ok(#(_ch, _, cut_end, _style, _err)) = list.at(rendered, end)
      let is_letters = is_var(data) || is_tag(data) || is_num(data)
      let #(path, cut_start) = case cut_start < 0 && is_letters {
        True -> {
          let assert Ok(#(_ch, path, cut_start, _style, _err)) =
            list.at(rendered, start - 1)
          #(path, cut_start + 1)
        }
        False -> #(path, cut_start)
      }
      // /Only move left if letter, not say comma, but is it weird to have commands available in insert mode
      // probably but let's try and push as many things to insert mode do command mode not needed
      // I would do this if CTRL functions not so overloaded
      // key press on vacant same in insert and cmd mode
      let #(p2, cut_end) = case cut_end < 0 {
        True -> {
          let assert Ok(#(_ch, path, cut_end, _style, _err)) =
            list.at(rendered, end - 1)
          #(path, cut_end + 1)
        }
        False -> #(path, cut_end)
      }
      case path != p2 || cut_start < 0 {
        // TODO need to think about commas in blocks?
        True -> {
          #(state, start, [])
        }
        _ -> {
          let assert Ok(#(target, rezip)) = zipper.at(state.source, path)
          io.debug(target)
          // always the same path
          let #(new, sub, offset, text_only) = case target {
            e.Lambda(param, body) -> {
              let #(param, offset) = replace_at(param, cut_start, cut_end, data)
              #(e.Lambda(param, body), [], offset, True)
            }
            e.Apply(e.Apply(e.Cons, _), _) -> {
              let new = e.Apply(e.Apply(e.Cons, e.Vacant("")), target)
              #(new, [0, 1], 0, False)
            }
            e.Apply(e.Apply(e.Extend(label), value), rest) -> {
              case data, cut_start <= 0 {
                ",", True -> {
                  let new = e.Apply(e.Apply(e.Extend(""), e.Vacant("")), target)
                  #(new, [], 0, True)
                }
                _, _ -> {
                  let #(label, offset) =
                    replace_at(label, cut_start, cut_end, data)
                  #(
                    e.Apply(e.Apply(e.Extend(label), value), rest),
                    [],
                    offset,
                    True,
                  )
                }
              }
            }
            e.Apply(e.Apply(e.Overwrite(label), value), rest) -> {
              case data, cut_start <= 0 {
                ",", True -> {
                  let new =
                    e.Apply(e.Apply(e.Overwrite(""), e.Vacant("")), target)
                  #(new, [], 0, True)
                }
                _, _ -> {
                  let #(label, offset) =
                    replace_at(label, cut_start, cut_end, data)
                  #(
                    e.Apply(e.Apply(e.Overwrite(label), value), rest),
                    [],
                    offset,
                    True,
                  )
                }
              }
            }
            e.Let(label, value, then) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Let(label, value, then), [], offset, True)
            }
            e.Variable(label) -> {
              case is_var(data) || is_num(data) && cut_start > 0 {
                True -> {
                  let #(label, offset) =
                    replace_at(label, cut_start, cut_end, data)
                  let #(new, text_only) = case label {
                    "" -> #(e.Vacant(""), False)
                    _ -> #(e.Variable(label), True)
                  }
                  #(new, [], offset, text_only)
                }
                False ->
                  case data {
                    "{" -> #(
                      e.Apply(e.Apply(e.Overwrite(""), e.Vacant("")), target),
                      [],
                      0,
                      False,
                    )
                    _ -> #(target, [], cut_start, True)
                  }
              }
            }

            e.Vacant(_) ->
              case data {
                "\"" -> #(e.Str(""), [], 0, False)
                "[" -> #(e.Tail, [], 0, False)
                "{" -> #(e.Empty, [], 0, False)
                // TODO need to add path to step in
                "(" -> #(e.Apply(e.Vacant(""), e.Vacant("")), [], 0, False)
                "=" -> #(e.Let("", e.Vacant(""), e.Vacant("")), [], 0, False)
                "|" -> #(
                  e.Apply(e.Apply(e.Case(""), e.Vacant("")), e.Vacant("")),
                  [],
                  0,
                  False,
                )
                "^" -> #(e.Perform(""), [], 0, False)
                _ -> {
                  case int.parse(data) {
                    Ok(number) -> #(
                      e.Integer(number),
                      [],
                      string.length(data),
                      False,
                    )
                    Error(Nil) ->
                      case is_var(data) {
                        True -> #(
                          e.Variable(data),
                          [],
                          string.length(data),
                          False,
                        )
                        False ->
                          case is_tag(data) {
                            True -> #(
                              e.Tag(data),
                              [],
                              string.length(data),
                              False,
                            )
                            False -> #(target, [], cut_start, True)
                          }
                      }
                  }
                }
              }
            e.Str(value) -> {
              let value = stringx.replace_at(value, cut_start, cut_end, data)
              #(e.Str(value), [], cut_start + string.length(data), True)
            }
            e.Integer(value) -> {
              case data == "-" && cut_start == 0 {
                True -> #(e.Integer(0 - value), [], 1, True)
                False ->
                  case int.parse(data) {
                    Ok(_) -> {
                      let assert Ok(value) =
                        int.to_string(value)
                        |> stringx.replace_at(cut_start, cut_end, data)
                        |> int.parse()
                      #(
                        e.Integer(value),
                        [],
                        cut_start + string.length(data),
                        True,
                      )
                    }
                    Error(Nil) -> #(target, [], cut_start, False)
                  }
              }
            }
            e.Tail -> {
              case data {
                "," -> #(
                  e.Apply(e.Apply(e.Cons, e.Vacant("")), e.Vacant("")),
                  [0, 1],
                  cut_start,
                  False,
                )
                _ -> #(target, [], cut_start, True)
              }
            }
            e.Empty -> {
              case data {
                "," -> #(
                  e.Apply(e.Apply(e.Extend(""), e.Vacant("")), e.Vacant("")),
                  [0, 1],
                  cut_start,
                  False,
                )
                _ -> #(target, [], cut_start, True)
              }
            }
            e.Extend(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Extend(label), [], offset, True)
            }
            e.Select(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Select(label), [], offset, True)
            }
            e.Overwrite(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Overwrite(label), [], offset, True)
            }
            e.Tag(label) -> {
              case is_tag(data) {
                True -> {
                  let #(label, offset) =
                    replace_at(label, cut_start, cut_end, data)
                  #(e.Tag(label), [], offset, True)
                }
                False -> #(target, [], cut_start, False)
              }
            }
            e.Apply(e.Apply(e.Case(label), value), rest) -> {
              case is_tag(data) {
                True -> {
                  let #(label, offset) =
                    replace_at(label, cut_start, cut_end, data)
                  #(
                    e.Apply(e.Apply(e.Case(label), value), rest),
                    [],
                    offset,
                    True,
                  )
                }
                False -> #(target, [], cut_start, False)
              }
            }
            e.Case(label) -> {
              case is_tag(data) {
                True -> {
                  let #(label, offset) =
                    replace_at(label, cut_start, cut_end, data)
                  #(e.Case(label), [], offset, True)
                }
                False -> #(target, [], cut_start, False)
              }
            }
            e.Perform(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Perform(label), [], offset, True)
            }
            e.Handle(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Handle(label), [], offset, True)
            }
            e.Shallow(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Shallow(label), [], offset, True)
            }
            e.Builtin(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Builtin(label), [], offset, True)
            }
            node -> {
              io.debug(#("nothing", node))
              #(node, [], cut_start, False)
            }
          }
          case target == new {
            True -> #(state, start, [])
            False -> {
              let new = rezip(new)
              let backwards = case state.history.1 {
                [#(original, p, True), ..rest] if p == path && text_only -> {
                  [#(original, path, True), ..rest]
                }
                _ -> [#(state.source, path, True), ..state.history.1]
              }
              let history = #([], backwards)
              // TODO move to update source

              let inferred = case state.auto_infer {
                True -> Some(do_infer(new, state.env))
                False -> None
              }

              let rendered =
                print.print(new, Some(path), state.auto_infer, inferred)
              // zip and target

              // update source source have a offset function
              let path = list.append(path, sub)
              let assert Ok(start) =
                dict.get(rendered.1, print.path_to_string(path))
              #(
                Embed(
                  ..state,
                  source: new,
                  history: history,
                  inferred: inferred,
                  focus: Some(path),
                  rendered: rendered,
                ),
                start + offset,
                [],
              )
            }
          }
        }
      }
    }
  }
}

fn replace_at(label, start, end, data) {
  let start = int.min(string.length(label), start)
  let label = stringx.replace_at(label, start, end, data)
  #(label, start + string.length(data))
}

fn run(state: Embed) {
  let #(_lift, _resume, handler) = effect.window_alert()

  let source = state.source
  let #(env, _sub, _next, _tenv) = state.env
  let handlers =
    dict.new()
    |> dict.insert("Alert", handler)
    |> dict.insert("Choose", effect.choose().2)
    |> dict.insert("HTTP", effect.http().2)
    |> dict.insert("Await", effect.await().2)
    |> dict.insert("Async", browser.async().2)
    |> dict.insert("Log", effect.debug_logger().2)
  let ret = execute(source, env, handlers)
  case ret {
    // Only render promises if we are in Async return.
    // returning a promise as a value should be rendered as a promise value
    // could allow await effect by assuming is in async context
    Error(#(break.UnhandledEffect("Await", v.Promise(_p)), _, _, _)) -> {
      let p =
        promise.map(r.await(ret), fn(final) {
          let message = case final {
            Error(#(reason, _rev, _env, _k)) -> reason_to_string(reason)
            Ok(term) -> {
              io.debug(term)
              term_to_string(term)
            }
          }
          fn(state) { Embed(..state, mode: Command(message)) }
        })

      #("Running", [p])
    }
    Error(#(reason, _rev, _env, _k)) -> #(reason_to_string(reason), [])
    Ok(term) -> #(term_to_string(term), [])
  }
}

fn reason_to_string(reason) {
  break.reason_to_string(reason)
}

fn term_to_string(term) {
  v.debug(term)
}

pub fn undo(state: Embed, start) {
  let assert Ok(#(_ch, current_path, _cut_start, _style, _err)) =
    list.at(state.rendered.0, start)
  case state.history.1 {
    [] -> #(Embed(..state, mode: Command("no undo available")), start, [])
    [edit, ..backwards] -> {
      let #(old, path, text_only) = edit
      // TODO put inference in history
      let inferred = case state.auto_infer {
        True -> Some(do_infer(old, state.env))
        False -> None
      }
      let rendered = print.print(old, state.focus, state.auto_infer, inferred)
      let assert Ok(start) = dict.get(rendered.1, print.path_to_string(path))
      let state =
        Embed(
          ..state,
          mode: Command(""),
          source: old,
          // I think text only get's off by one here
          history: #(
            [#(state.source, current_path, text_only), ..state.history.0],
            backwards,
          ),
          inferred: inferred,
          rendered: rendered,
        )
      #(state, start, [])
    }
  }
}

pub fn redo(state: Embed, start) {
  let assert Ok(#(_ch, current_path, _cut_start, _style, _err)) =
    list.at(state.rendered.0, start)
  case state.history.0 {
    [] -> #(Embed(..state, mode: Command("no redo available")), start, [])
    [edit, ..forward] -> {
      let #(other, path, text_only) = edit
      let inferred = case state.auto_infer {
        True -> Some(do_infer(other, state.env))
        False -> None
      }
      let rendered = print.print(other, state.focus, state.auto_infer, inferred)
      let assert Ok(start) = dict.get(rendered.1, print.path_to_string(path))
      let state =
        Embed(
          ..state,
          mode: Command(""),
          source: other,
          // I think text only get's off by one here
          history: #(forward, [
            #(state.source, current_path, text_only),
            ..state.history.1
          ]),
          inferred: inferred,
          rendered: rendered,
        )
      #(state, start, [])
    }
  }
}

pub fn builtin(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    e.Vacant(_) -> #(e.Builtin(""), Insert, [])
    _ -> #(e.Apply(e.Builtin(""), target), Insert, [0])
  }
}

// update_at is a utility that might get extracted to transform
// but focus and state are all part of this specific embed model
pub fn call_with(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Apply(e.Vacant(""), target), state.mode, [0])
}

pub fn assign_to(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Let("", target, e.Vacant("")), Insert, [])
}

pub fn assign_before(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Let("", e.Vacant(""), target), Insert, [])
}

pub fn extend(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    e.Vacant("") -> #(e.Empty, state.mode, [])
    _ -> #(e.Apply(e.Apply(e.Extend(""), e.Vacant("")), target), Insert, [])
  }
}

pub fn extender(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use _target <- update_at(state, path)
  #(e.Extend(""), state.mode, [])
}

pub fn tag(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    // e.Vacant("") -> #(e.Empty, state.mode, [])
    _ -> #(e.Apply(e.Tag(""), target), Insert, [0])
  }
}

fn copy(state: Embed, start, end) {
  use path <- single_focus(state, start, end)

  case zipper.at(state.source, path) {
    Error(Nil) -> panic("how did this happen need path back")
    Ok(#(target, _rezip)) -> {
      #(Embed(..state, yanked: Some(target)), start, [])
    }
  }
}

fn paste(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  // TODO return error for nothing on clip board
  #(option.unwrap(state.yanked, target), state.mode, [])
}

pub fn overwrite(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Apply(e.Apply(e.Overwrite(""), e.Vacant("")), target), Insert, [])
}

pub fn perform(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    e.Vacant(_) -> #(e.Perform(""), Insert, [])
    _ -> #(e.Apply(e.Perform(""), target), Insert, [0])
  }
}

pub fn string(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use _target <- update_at(state, path)
  #(e.Str(""), Insert, [])
}

pub fn binary(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use _target <- update_at(state, path)
  #(e.Binary(<<1, 10, 100>>), Insert, [])
}

// shift d for delete line
pub fn delete(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    e.Let(_, _, then) -> #(then, state.mode, [])
    e.Apply(e.Apply(e.Cons, _), rest) -> #(rest, state.mode, [])
    e.Apply(e.Apply(e.Extend(_), _), rest) -> #(rest, state.mode, [])
    e.Apply(e.Apply(e.Overwrite(_), _), rest) -> #(rest, state.mode, [])
    e.Apply(e.Apply(e.Case(_), _), then) -> #(then, state.mode, [])
    _ -> #(e.Vacant(""), state.mode, [])
  }
}

pub fn insert_function(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Lambda("", target), Insert, [])
}

pub fn select(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Apply(e.Select(""), target), Insert, [0])
}

pub fn handle(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    e.Vacant(_) -> #(e.Handle(""), Insert, [])
    _ -> #(e.Apply(e.Handle(""), target), Insert, [0])
  }
}

pub fn shallow(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    e.Vacant(_) -> #(e.Shallow(""), Insert, [])
    _ -> #(e.Apply(e.Shallow(""), target), Insert, [0])
  }
}

pub fn list_element(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  // without this vacant case how do you make an empty list
  let new = case target {
    e.Vacant(_) -> e.Tail
    _ -> e.Apply(e.Apply(e.Cons, target), e.Tail)
  }
  #(new, state.mode, [])
}

pub fn extend_list(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  // without this vacant case how do you make an empty list
  let new = case target {
    e.Apply(e.Apply(e.Cons, _), _) | e.Tail ->
      e.Apply(e.Apply(e.Cons, e.Vacant("")), target)
    _ -> target
  }
  #(new, state.mode, [])
}

pub fn spread_list(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  // without this vacant case how do you make an empty list
  let new = case target {
    e.Apply(e.Apply(e.Cons, item), e.Tail) -> item
    e.Tail -> e.Vacant("")
    _ -> target
  }
  #(new, state.mode, [])
}

pub fn call(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Apply(target, e.Vacant("")), state.mode, [1])
}

pub fn number(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use _target <- update_at(state, path)
  #(e.Integer(0), Insert, [])
}

pub fn match(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Apply(e.Apply(e.Case(""), e.Vacant("")), target), Insert, [])
}

pub fn nocases(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use _target <- update_at(state, path)
  #(e.NoCases, state.mode, [])
}

pub fn insert_paragraph(index, state: Embed) {
  let assert Ok(#(_ch, path, offset, _style, _err)) =
    list.at(state.rendered.0, index)
  let source = state.source
  let assert Ok(#(target, rezip)) = zipper.at(source, path)

  let #(new, sub, offset) = case target {
    e.Str(content) -> {
      // needs end for large enter, needs to be insert mode only
      let #(content, offset) = replace_at(content, offset, offset, "\n")
      #(e.Str(content), [], offset)
    }
    e.Let(label, value, then) -> {
      #(e.Let(label, value, e.Let("", e.Vacant(""), then)), [1], 0)
    }
    node -> #(e.Let("", node, e.Vacant("")), [1], 0)
  }
  let new = rezip(new)
  let history = #([], [#(source, path, False), ..state.history.1])

  let inferred = case
    state.auto_infer
    |> io.debug
  {
    True -> Some(do_infer(new, state.env))
    False -> None
  }

  let rendered = print.print(new, Some(path), state.auto_infer, inferred)
  let assert Ok(start) =
    dict.get(rendered.1, print.path_to_string(list.append(path, sub)))
  #(
    Embed(
      ..state,
      mode: Insert,
      source: new,
      history: history,
      inferred: inferred,
      rendered: rendered,
      focus: Some(path),
    ),
    start + offset,
  )
}

pub fn html(embed: Embed) {
  embed.rendered.0
  |> group
  |> to_html()
}

// reuse single focus with error
pub fn update_selection(state: Embed, start, end) {
  case list.at(state.rendered.0, start) {
    Error(Nil) -> Embed(..state, focus: None)
    Ok(#(_ch, path, _cut_start, _style, _err)) -> {
      case list.at(state.rendered.0, end) {
        Error(Nil) -> Embed(..state, focus: None)
        Ok(#(_ch, p2, _cut_end, _style, _err)) ->
          case path != p2 {
            True -> {
              Embed(..state, focus: None)
            }
            False -> {
              Embed(..state, focus: Some(path))
            }
          }
      }
    }
  }
}

pub fn pallet(embed: Embed) {
  case embed.mode {
    Command(warning) -> {
      let message = case warning {
        "" ->
          case embed.inferred, embed.focus {
            types, Some(path) -> {
              case print.type_at(path, types) {
                Some(Ok(_)) -> "press space to run"
                Some(Error(#(r, t1, t2))) -> {
                  type_.render_failure(r, t1, t2)
                }
                None -> "press space to type check"
              }
            }
            _, _ -> "press space to run"
          }

        message -> message
      }
      string.append(":", message)
    }
    Insert -> "insert"
  }
}

fn to_html(sections) {
  list.fold(sections, "", fn(acc, section) {
    let #(style, err, letters) = section
    let class = case style {
      print.Default -> []
      print.Keyword -> ["text-gray-500"]
      print.Missing -> ["text-pink-3"]
      print.Hole -> ["text-orange-4 font-bold"]
      print.Integer -> ["text-purple-4"]
      print.String -> ["text-green-4"]
      print.Label -> ["text-blue-3"]
      print.Effect -> ["text-yellow-4"]
      print.Builtin -> ["italic underline"]
    }
    let class =
      case err {
        False -> class
        True -> list.append(class, ["border-b-2 border-orange-4"])
      }
      |> string.join(" ")
    string.concat([
      acc,
      "<span class=\"",
      class,
      "\">",
      escape_html(string.concat(letters)),
      "</span>",
    ])
  })
}

fn escape_html(source) {
  source
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

fn group(rendered: List(print.Rendered)) {
  case rendered {
    [] -> []
    [#(ch, _path, _offset, style, err), ..rendered] ->
      do_group(rendered, [ch], [], style, err)
  }
}

fn do_group(rest, current, acc, style, err) {
  case rest {
    [] -> list.reverse([#(style, err, list.reverse(current)), ..acc])
    [#(ch, _path, _offset, s, e), ..rest] ->
      case s == style && e == err {
        True -> do_group(rest, [ch, ..current], acc, style, err)
        False ->
          do_group(
            rest,
            [ch],
            [#(style, err, list.reverse(current)), ..acc],
            s,
            e,
          )
      }
  }
}

pub fn blur(state) {
  escape(state)
}

pub fn escape(state) {
  Embed(..state, mode: Command(""))
}

fn single_focus(state: Embed, start, end, cb) {
  case list.at(state.rendered.0, start) {
    Error(Nil) -> #(state, start, [])
    Ok(#(_ch, path, _cut_start, _style, _err)) -> {
      case list.at(state.rendered.0, end) {
        Error(Nil) -> #(state, start, [])
        Ok(#(_ch, p2, _cut_end, _style, _err)) ->
          case path != p2 {
            True -> {
              #(state, start, [])
            }
            False -> cb(path)
          }
      }
    }
  }
}

fn update_at(state: Embed, path, cb) {
  let source = state.source
  case zipper.at(source, path) {
    Error(Nil) -> panic("how did this happen need path back")
    Ok(#(target, rezip)) -> {
      let #(updated, mode, sub_path) = cb(target)
      let new = rezip(updated)
      let history = #([], [#(source, path, False), ..state.history.1])
      let inferred = case state.auto_infer {
        True -> Some(do_infer(new, state.env))
        False -> None
      }
      let rendered = print.print(new, state.focus, state.auto_infer, inferred)
      let path = list.append(path, sub_path)
      let assert Ok(start) = dict.get(rendered.1, print.path_to_string(path))
      #(
        Embed(
          ..state,
          mode: mode,
          source: new,
          history: history,
          // TODO linger for infer
          // TODO place for editor utils location path etc
          // type check is needed for any infer change on labels
          // Proper entry for all my apps plinth for selection chagne etc
          // ideadlly start super fast in web worker
          inferred: inferred,
          rendered: rendered,
        ),
        start,
        [],
      )
    }
  }
}
