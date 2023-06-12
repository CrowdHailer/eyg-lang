import gleam/io
import gleam/int
import gleam/list
import gleam/map
import gleam/mapx
import gleam/option.{None, Option, Some}
import gleam/regex
import gleam/result
import gleam/string
import gleam/stringx
import eygir/expression as e
import eygir/encode
import eygir/decode
import eyg/runtime/interpreter as r
import harness/stdlib
import harness/effect
import eyg/analysis/jm/tree
import eyg/analysis/jm/type_ as t
import easel/print
import easel/zipper
import atelier/view/type_
import gleam/javascript
import gleam/javascript/promise
import plinth/javascript/promisex
import plinth/browser/window
import plinth/browser/document
import plinth/browser/console

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
// unwrap/copy+paste
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
    std: Option(#(e.Expression, tree.State)),
    source: e.Expression,
    history: History,
    auto_infer: Bool,
    inferred: Option(tree.State),
    rendered: #(List(print.Rendered), map.Map(String, Int)),
    focus: Option(List(Int)),
  )
}

// infer continuation
fn do_infer(source, std) {
  case std {
    Some(#(_e, state)) -> {
      let #(sub, next, types) = state
      let assert Ok(Ok(t)) = map.get(types, [])
      let env = mapx.singleton("std", #([], t))
      tree.infer_env(source, t.Var(-1), t.Var(-2), env, sub, next)
    }
    None ->
      // TODO real effects
      tree.infer(source, t.Var(-1), t.Var(-2))
  }
}

pub fn fullscreen(root) {
  let source = e.Vacant("")
  let inferred = do_infer(source, None)
  let rendered = print.print(source, None, Some(inferred))
  let state =
    Embed(
      Command(""),
      None,
      None,
      source,
      #([], []),
      False,
      Some(inferred),
      rendered,
      None,
    )
  let ref = javascript.make_reference(state)
  document.add_event_listener(
    root,
    "click",
    fn(event) {
      let target = document.target(event)
      case document.closest(target, "[data-click]") {
        Ok(element) -> {
          let assert Ok(handle) = document.dataset_get(element, "click")
          case handle {
            "load" -> {
              promise.map(
                window.show_open_file_picker(),
                fn(value) {
                  let #(file_handle) = value
                  use file <- promise.map(window.get_file(file_handle))
                  use text <- promise.map(window.file_text(file))
                  let assert Ok(source) = decode.from_json(text)

                  javascript.update_reference(
                    ref,
                    fn(state: Embed) {
                      // always infer at the start
                      let inferred = do_infer(source, state.std)

                      let rendered =
                        print.print(source, Some([]), Some(inferred))
                      let assert Ok(start) =
                        map.get(rendered.1, print.path_to_string([]))

                      let state =
                        Embed(
                          ..state,
                          source: source,
                          inferred: Some(inferred),
                          rendered: rendered,
                        )
                      render_page(root, start, state)
                      state
                    },
                  )
                },
              )

              Nil
            }
            _ -> {
              io.debug(handle)
              Nil
            }
          }
          Nil
        }
        Error(Nil) -> Nil
      }
    },
  )
  document.add_event_listener(
    root,
    "beforeinput",
    fn(event) {
      document.prevent_default(event)
      handle_input(
        event,
        fn(data, start, end) {
          javascript.update_reference(
            ref,
            fn(state) {
              let #(state, start) = insert_text(state, data, start, end)
              render_page(root, start, state)
              state
            },
          )
          Nil
        },
        fn(start) {
          javascript.update_reference(
            ref,
            fn(state) {
              let #(state, start) = insert_paragraph(start, state)
              render_page(root, start, state)
              state
            },
          )
          // todo pragraph
          io.debug(#(start))
          Nil
        },
      )
    },
  )
  document.add_event_listener(
    root,
    "keydown",
    fn(event) {
      case
        case document.key(event) {
          "Escape" -> {
            javascript.update_reference(
              ref,
              fn(s) {
                let s = escape(s)
                render_page(root, 1, s)
                s
              },
            )
            Ok(Nil)
          }
          _ -> Error(Nil)
        }
      {
        Ok(Nil) -> document.prevent_default(event)
        Error(Nil) -> Nil
      }
    },
  )
  document.add_event_listener(
    // event can have phantom type which is the internal event type
    document.document(),
    "selectionchange",
    fn(_event) {
      let r = {
        use selection <- result.then(window.get_selection())
        use range <- result.then(window.get_range_at(selection, 0))
        Ok(range)
      }

      io.debug(r)
      Nil
    },
  )
  document.set_html(
    root,
    "<div data-click=\"load\" class=\"cover expand vstack pointer\"><span>click to load</span></div>",
  )
  Nil
}

fn render_page(root, start, state) {
  case document.query_selector(root, "pre") {
    Ok(pre) -> {
      // updating the contenteditable node messes with cursor placing
      document.set_html(pre, html(state))
      let pallet_span = document.next_element_sibling(pre)
      document.set_html(pallet_span, pallet(state))
    }

    Error(Nil) -> {
      let content =
        string.concat([
          "<pre class=\"expand overflow-auto outline-none w-full my-1 mx-4 px-4\" contenteditable spellcheck=\"false\">",
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

pub external fn handle_input(
  document.Event,
  insert_text: fn(String, Int, Int) -> Nil,
  insert_paragraph: fn(Int) -> Nil,
) -> Nil =
  "../easel_ffi.js" "handleInput"

// relies on a flat list of spans
pub external fn place_cursor(document.Element, Int) -> Nil =
  "../easel_ffi.js" "placeCursor"

pub fn init(json) {
  let assert Ok(source) = decode.decoder(json)
  // inferred std is cached
  let #(std, source) = case source {
    e.Let("std", std, e.Lambda("_", body)) -> {
      let state = tree.infer(std, t.Var(-3), t.Var(-4))
      #(Some(#(std, state)), body)
    }
    // if don't capture std then add unit
    e.Lambda("_", body) -> {
      let std = e.Empty
      let state = tree.infer(std, t.Var(-3), t.Var(-4))
      #(Some(#(std, state)), body)
    }
    e.Let("std", _std, other) -> {
      // Capture is capturing multiple times needs some tests
      io.debug(other)
      panic("sss")
    }
    _ -> {
      io.debug(source)
      #(None, source)
    }
  }
  // can keep inferred in history
  let inferred = do_infer(source, std)
  let rendered = print.print(source, None, Some(inferred))
  Embed(
    Command(""),
    None,
    std,
    source,
    #([], []),
    True,
    Some(inferred),
    rendered,
    None,
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

pub fn insert_text(state: Embed, data, start, end) {
  let rendered = state.rendered.0
  case state.mode {
    Command(_) -> {
      case data {
        " " -> {
          let message = run(state)
          let state = Embed(..state, mode: Command(message))
          #(state, start)
        }
        "q" -> {
          io.print(encode.to_json(state.source))
          #(state, start)
        }
        "w" -> call_with(state, start, end)
        "e" -> assign_to(state, start, end)
        "r" -> extend(state, start, end)
        "t" -> tag(state, start, end)
        "y" -> copy(state, start, end)
        "Y" -> paste(state, start, end)
        "i" -> #(Embed(..state, mode: Insert), start)
        "[" | "x" -> list_element(state, start, end)
        "o" -> overwrite(state, start, end)
        "p" -> perform(state, start, end)
        "s" -> string(state, start, end)
        "d" -> delete(state, start, end)
        "f" -> insert_function(state, start, end)
        "g" -> select(state, start, end)
        "h" -> handle(state, start, end)
        "z" -> undo(state, start)
        "Z" -> redo(state, start)
        "c" -> call(state, start, end)
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
          #(Embed(..state, mode: mode), start)
        }
      }
    }
    Insert -> {
      let assert Ok(#(_ch, path, cut_start, _style, _err)) =
        list.at(rendered, start)
      let assert Ok(#(_ch, _, cut_end, _style, _err)) = list.at(rendered, end)
      let is_letters = is_var(data) || is_tag(data)
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
          #(state, start)
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
              case is_var(data) {
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
                "\"" -> #(e.Binary(""), [], 0, False)
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
            e.Binary(value) -> {
              let value = stringx.replace_at(value, cut_start, cut_end, data)
              #(e.Binary(value), [], cut_start + string.length(data), True)
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
            e.Perform(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Perform(label), [], offset, True)
            }
            e.Handle(label) -> {
              let #(label, offset) = replace_at(label, cut_start, cut_end, data)
              #(e.Handle(label), [], offset, True)
            }
            node -> {
              io.debug(#("nothing", node))
              #(node, [], cut_start, False)
            }
          }
          case target == new {
            True -> #(state, start)
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
                True -> Some(do_infer(new, state.std))
                False -> None
              }

              let rendered = print.print(new, Some(path), inferred)
              // zip and target

              // update source source have a offset function
              let path = list.append(path, sub)
              let assert Ok(start) =
                map.get(rendered.1, print.path_to_string(path))
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

  let source = case state.std {
    Some(#(std, _)) -> e.Let("std", std, state.source)
    None -> state.source
  }
  let handlers =
    map.new()
    |> map.insert("Alert", handler)
  let env = stdlib.env()
  case r.handle(r.eval(source, env, r.Value), env.builtins, handlers) {
    r.Abort(reason) -> reason_to_string(reason)
    r.Value(term) -> term_to_string(term)
    _ -> panic("this should be tackled better in the run code")
  }
}

fn reason_to_string(reason) {
  case reason {
    r.UndefinedVariable(var) -> string.append("variable undefined: ", var)
    r.IncorrectTerm(expected, got) ->
      string.concat([
        "unexpected term, expected: ",
        expected,
        " got: ",
        term_to_string(got),
      ])
    r.MissingField(field) -> string.concat(["missing record field: ", field])
    r.NoCases -> string.concat(["no cases matched"])
    r.NotAFunction(term) ->
      string.concat(["function expected got: ", term_to_string(term)])
    r.UnhandledEffect(effect, _with) ->
      string.concat(["unhandled effect ", effect])
    r.Vacant(note) -> string.concat(["tried to run a todo: ", note])
  }
}

fn term_to_string(term) {
  r.to_string(term)
  // case term {
  //   r.Binary(value) -> string.concat(["\"", value, "\""])
  //   _ -> "non string term"
  // }
}

pub fn undo(state: Embed, start) {
  let assert Ok(#(_ch, current_path, _cut_start, _style, _err)) =
    list.at(state.rendered.0, start)
  case state.history.1 {
    [] -> #(Embed(..state, mode: Command("no undo available")), start)
    [edit, ..backwards] -> {
      let #(old, path, text_only) = edit
      // TODO put inference in history
      let inferred = case state.auto_infer {
        True -> Some(do_infer(old, state.std))
        False -> None
      }
      let rendered = print.print(old, state.focus, inferred)
      let assert Ok(start) = map.get(rendered.1, print.path_to_string(path))
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
      #(state, start)
    }
  }
}

pub fn redo(state: Embed, start) {
  let assert Ok(#(_ch, current_path, _cut_start, _style, _err)) =
    list.at(state.rendered.0, start)
  case state.history.0 {
    [] -> #(Embed(..state, mode: Command("no redo available")), start)
    [edit, ..forward] -> {
      let #(other, path, text_only) = edit
      let inferred = case state.auto_infer {
        True -> Some(do_infer(other, state.std))
        False -> None
      }
      let rendered = print.print(other, state.focus, inferred)
      let assert Ok(start) = map.get(rendered.1, print.path_to_string(path))
      let state =
        Embed(
          ..state,
          mode: Command(""),
          source: other,
          // I think text only get's off by one here
          history: #(
            forward,
            [#(state.source, current_path, text_only), ..state.history.1],
          ),
          inferred: inferred,
          rendered: rendered,
        )
      #(state, start)
    }
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

pub fn extend(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    e.Vacant("") -> #(e.Empty, state.mode, [])
    _ -> #(e.Apply(e.Apply(e.Extend(""), e.Vacant("")), target), Insert, [])
  }
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
      #(Embed(..state, yanked: Some(target)), start)
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
  #(e.Binary(""), Insert, [])
}

// shift d for delete line
pub fn delete(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  case target {
    e.Let(_, _, then) -> #(then, state.mode, [])
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

pub fn list_element(state: Embed, start, end) {
  use path <- single_focus(state, start, end)
  use target <- update_at(state, path)
  #(e.Apply(e.Apply(e.Cons, target), e.Tail), state.mode, [])
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
  let assert Ok(#(_ch, path, _offset, _style, _err)) =
    list.at(state.rendered.0, index)
  let source = state.source
  let assert Ok(#(target, rezip)) = zipper.at(source, path)

  let new = case target {
    e.Let(label, value, then) -> {
      e.Let(label, value, e.Let("", e.Vacant(""), then))
    }
    node -> e.Let("", node, e.Vacant(""))
  }
  let new = rezip(new)
  let history = #([], [#(source, path, False), ..state.history.1])

  let inferred = case
    state.auto_infer
    |> io.debug
  {
    True -> Some(do_infer(new, state.std))
    False -> None
  }

  let rendered = print.print(new, Some(path), inferred)
  let assert Ok(start) =
    map.get(rendered.1, print.path_to_string(list.append(path, [1])))
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
    start,
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
  //     }
  //   }
  // }
  // None -> Embed(..state, path: None)
  // }
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
  list.fold(
    sections,
    "",
    fn(acc, section) {
      let #(style, err, letters) = section
      let class = case style {
        print.Default -> []
        print.Keyword -> ["text-gray-500"]
        print.Missing -> ["text-pink-3"]
        print.Hole -> ["text-orange-4 font-bold"]
        print.Integer -> ["text-purple-4"]
        print.String -> ["text-green-4"]
        print.Union -> ["text-blue-3"]
        print.Effect -> ["text-yellow-4"]
        print.Builtin -> ["font-italic"]
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
        string.concat(letters),
        "</span>",
      ])
    },
  )
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
    Error(Nil) -> #(state, start)
    Ok(#(_ch, path, _cut_start, _style, _err)) -> {
      case list.at(state.rendered.0, end) {
        Error(Nil) -> #(state, start)
        Ok(#(_ch, p2, _cut_end, _style, _err)) ->
          case path != p2 {
            True -> {
              #(state, start)
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
        True -> Some(do_infer(new, state.std))
        False -> None
      }
      let rendered = print.print(new, state.focus, inferred)
      let path = list.append(path, sub_path)
      let assert Ok(start) = map.get(rendered.1, print.path_to_string(path))
      #(
        Embed(
          ..state,
          mode: mode,
          source: new,
          history: history,
          // TODO linger for infer
          // TODO linger for open editor
          // TODO place for editor utils location path etc
          // type check is needed for any infer change on labels
          // Proper entry for all my apps plinth for selection chagne etc
          // ideadlly start super fast in web worker
          inferred: inferred,
          rendered: rendered,
        ),
        start,
      )
    }
  }
}
