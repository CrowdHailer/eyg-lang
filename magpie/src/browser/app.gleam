import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/result
import gleam/string
import lustre
import lustre/effect as cmd
import lustre/element.{text}
import lustre/element/html as el
import lustre/event
import lustre/attribute.{class}
import magpie/store/in_memory.{B, I, L, S}
import magpie/query.{v}
import browser/hash
import browser/worker
import browser/serialize

// At the top to get generic
// TODO listx
fn delete_at(items, i) {
  let pre = list.take(items, i)
  let post = list.drop(items, i + 1)
  list.flatten([pre, post])
}

// TODO listx
fn map_at(items, i, f) {
  use item <- result.then(list.at(items, i))
  let pre = list.take(items, i)
  let post = list.drop(items, i + 1)
  Ok(list.flatten([pre, [f(item)], post]))
}

@external(javascript, "../browser_ffi.mjs", "addEventListener")
fn add_event_listener(event: String, listener: fn(Nil) -> Nil) -> Nil

pub fn run() {
  let assert Ok(dispatch) =
    lustre.application(init, update, render)
    |> lustre.start("#app", Nil)

  add_event_listener("hashchange", fn(_) { dispatch(HashChange) })
}

pub type MatchSelection {
  Variable(value: String)
  ConstString(value: String)
  ConstInteger(value: Option(Int))
  ConstBoolean(value: Bool)
}

pub type Mode {
  OverView
  ChooseVariable(query: Int)
  UpdateMatch(query: Int, pattern: Int, match: Int, selection: MatchSelection)
}

pub type DBState {
  Indexing
  Querying(Int)
  Ready
}

pub type DB {
  DB(worker: worker.Worker, working: DBState, db_view: serialize.DBView)
}

pub type App {
  App(
    db: DB,
    queries: List(
      #(
        #(List(String), List(#(query.Match, query.Match, query.Match))),
        Option(List(List(in_memory.Value))),
      ),
    ),
    mode: Mode,
  )
}

pub type Action {
  Indexed(serialize.DBView)
  HashChange
  RunQuery(Int)
  QueryResult(List(List(in_memory.Value)))
  AddQuery
  DeleteQuery(Int)
  AddVariable(query: Int)
  SelectVariable(var: String)
  DeleteVariable(query: Int, variable: Int)
  AddPattern(query: Int)
  EditMatch(query: Int, pattern: Int, match: Int)
  EditMatchType(MatchSelection)
  ReplaceMatch
  DeletePattern(query: Int, pattern: Int)
  InputChange(new: String)
  CheckChange(new: Bool)
}

// choice in edit match, or form submit info in discord

pub fn init(_) {
  let w = worker.start_worker("./worker.js")
  #(
    App(DB(w, Indexing, serialize.DBView(0, [])), queries(), OverView),
    cmd.from(fn(dispatch) {
      worker.on_message(w, fn(raw) {
        case serialize.db_view().decode(raw) {
          Ok(db_view) -> dispatch(Indexed(db_view))
          Error(_) ->
            case serialize.relations().decode(raw) {
              Ok(relations) -> dispatch(QueryResult(relations))
              Error(_) -> {
                io.debug(#("unexpected message", raw))
                Nil
              }
            }
        }
      })
    }),
  )
}

@external(javascript, "../browser_ffi.mjs", "getHash")
fn get_hash() -> String

@external(javascript, "../browser_ffi.mjs", "setHash")
fn set_hash(hash: String) -> Nil

fn update_hash(queries) {
  cmd.from(fn(_dispatch) {
    set_hash(hash.encode(
      queries
      |> list.map(fn(x: #(_, _)) { x.0 }),
    ))
  })
}

pub fn update(state: App, action) {
  case action {
    Indexed(view) -> #(
      App(DB(state.db.worker, Ready, view), queries(), OverView),
      cmd.none(),
    )
    HashChange -> {
      let state = case state {
        App(db, _queries, _mode) -> App(db, queries(), OverView)
        other -> other
      }
      #(state, cmd.none())
    }
    RunQuery(i) -> {
      io.debug("running")

      let assert App(DB(db, Ready, view), queries, _mode) = state
      let assert Ok(queries) =
        map_at(queries, i, fn(q) {
          let #(#(from, where), _cache) = q

          worker.post_message(
            db,
            serialize.query().encode(serialize.Query(from, where)),
          )
          #(#(from, where), None)
        })
      #(App(DB(db, Querying(i), view), queries, OverView), cmd.none())
    }
    QueryResult(relations) -> {
      let assert App(DB(db, Querying(i), view), queries, _mode) = state
      let assert Ok(queries) =
        map_at(queries, i, fn(q) {
          let #(#(from, where), _cache) = q
          #(#(from, where), Some(relations))
        })
      #(App(..state, queries: queries, db: DB(db, Ready, view)), cmd.none())
    }
    AddQuery -> {
      let assert App(db, queries, mode) = state
      let queries = list.append(queries, [#(#([], []), None)])
      #(App(db, queries, mode), update_hash(queries))
    }
    DeleteQuery(i) -> {
      let assert App(db, queries, mode) = state
      let queries = delete_at(queries, i)
      #(App(db, queries, mode), update_hash(queries))
    }
    AddVariable(i) -> {
      let assert App(db, queries, _) = state
      #(App(db, queries, ChooseVariable(i)), cmd.none())
    }
    SelectVariable(var) -> {
      let assert App(db, queries, ChooseVariable(i)) = state
      let assert Ok(queries) =
        map_at(queries, i, fn(q) {
          let #(#(find, where), _) = q
          let find = [var, ..find]
          #(#(find, where), None)
        })
      #(App(db, queries, OverView), update_hash(queries))
    }
    DeleteVariable(i, j) -> {
      let assert App(db, queries, _) = state
      let assert Ok(queries) =
        map_at(queries, i, fn(q) {
          let #(#(find, where), _) = q
          #(#(delete_at(find, j), where), None)
        })
      #(App(db, queries, OverView), update_hash(queries))
    }
    AddPattern(i) -> {
      let assert App(db, queries, _) = state
      let assert Ok(queries) =
        map_at(queries, i, fn(q) {
          let #(#(find, where), _) = q
          let pattern = #(v("_"), v("_"), v("_"))
          let where = [pattern, ..where]
          #(#(find, where), None)
        })
      #(App(db, queries, OverView), update_hash(queries))
    }
    EditMatch(i, j, k) -> {
      let assert App(db, queries, _) = state
      let assert Ok(#(#(_find, where), _cache)) = list.at(queries, i)
      let assert Ok(pattern) = list.at(where, j)

      let match = case k {
        0 -> pattern.0
        1 -> pattern.1
        2 -> pattern.2
      }
      let selection = case match {
        query.Variable(var) -> Variable(var)
        query.Constant(S(value)) -> ConstString(value)
        query.Constant(I(value)) -> ConstInteger(Some(value))
        query.Constant(B(value)) -> ConstBoolean(value)
      }

      let mode = UpdateMatch(i, j, k, selection)
      #(App(db, queries, mode), cmd.none())
    }
    EditMatchType(selection) -> {
      let assert App(db, queries, UpdateMatch(i, j, k, _)) = state
      #(App(db, queries, UpdateMatch(i, j, k, selection)), cmd.none())
    }
    ReplaceMatch -> {
      let assert App(db, queries, UpdateMatch(i, j, k, selection)) = state
      let match = case selection {
        Variable(var) -> query.Variable(var)
        ConstString(value) -> query.s(value)
        ConstInteger(Some(value)) -> query.i(value)
        // if we have a discard could use that here
        ConstInteger(None) -> query.i(0)
        ConstBoolean(bool) -> query.b(bool)
      }
      let assert Ok(queries) =
        map_at(queries, i, fn(q) {
          let #(#(find, where), _cache) = q
          let assert Ok(where) =
            map_at(where, j, fn(pattern: query.Pattern) {
              case k {
                0 -> #(match, pattern.1, pattern.2)
                1 -> #(pattern.0, match, pattern.2)
                2 -> #(pattern.0, pattern.1, match)
              }
            })
          #(#(find, where), None)
        })
      #(App(db, queries, OverView), update_hash(queries))
    }

    DeletePattern(i, j) -> {
      let assert App(db, queries, _) = state
      let assert Ok(queries) =
        map_at(queries, i, fn(q) {
          let #(#(find, where), _) = q
          #(#(find, delete_at(where, j)), None)
        })
      #(App(db, queries, OverView), update_hash(queries))
    }
    InputChange(new) -> {
      let assert App(db, queries, UpdateMatch(i, j, k, selection)) = state
      let selection = case selection {
        Variable(_) -> Variable(new)
        ConstString(_) -> ConstString(new)
        ConstInteger(_) -> ConstInteger(option.from_result(int.parse(new)))
        ConstBoolean(_) -> todo("shouldn't happend because check change")
      }
      #(App(db, queries, UpdateMatch(i, j, k, selection)), cmd.none())
    }
    CheckChange(new) -> {
      let assert App(db, queries, UpdateMatch(i, j, k, selection)) = state
      let selection = case selection {
        ConstBoolean(_) -> ConstBoolean(new)
        _ -> todo("shouldn't happend because input change")
      }
      #(App(db, queries, UpdateMatch(i, j, k, selection)), cmd.none())
    }
  }
}

pub fn render(state) {
  let App(DB(_, state, view), queries, mode) = state
  el.div(
    [class("bg-gray-200 min-h-screen p-4")],
    list.flatten([
      render_edit(mode, view),
      render_notebook(state, view, queries, mode),
      render_examples(),
    ]),
  )
}

fn render_examples() {
  [
    el.div([class("max-w-4xl mx-auto p-4")], [
      el.div([class("text-gray-600 font-bold")], [text("Examples")]),
      el.a(
        [
          attribute.href(
            "#vmovie,smovie/year,vyear,r0,smovie/title,sAlien:1&i200,vattribute,vvalue:1,0&vdirector,sperson/name,vdirectorName,vmovie,smovie/director,r0,r2,smovie/title,vtitle,r2,smovie/cast,varnold,r4,sperson/name,sArnold Schwarzenegger:3,1",
          ),
        ],
        [text("movies")],
      ),
    ]),
  ]
}

fn render_edit(mode, db: serialize.DBView) {
  case mode {
    UpdateMatch(_, _, k, selection) -> [
      el.div(
        [
          class(
            "min-h-screen absolute bg-gray-200 top-0 bottom-0 left-0 right-0 ",
          ),
        ],
        [
          el.div(
            [class("flex flex-col justify-around min-h-full items-center")],
            [
              el.div(
                [
                  class(
                    "max-w-4xl w-full py-10 px-4 rounded-lg bg-gray-50 text-gray-800 border border-gray-400",
                  ),
                ],
                [
                  el.div([], [
                    el.h2([class("text-xl my-4 border-b")], [
                      text("update match"),
                    ]),
                  ]),
                  el.div([], [
                    el.button(
                      [
                        class(case selection {
                          Variable(_) ->
                            "mr-1 bg-blue-800 text-white rounded border border-blue-600 px-2"
                          _ -> "mr-1 rounded border border-blue-600 px-2"
                        }),
                        event.on_click(EditMatchType(Variable("x"))),
                      ],
                      [text("variable")],
                    ),
                    el.button(
                      [
                        class(case selection {
                          ConstString(_) ->
                            "mr-1 bg-blue-800 text-white rounded border border-blue-600 px-2"
                          _ -> "mr-1 rounded border border-blue-600 px-2"
                        }),
                        event.on_click(EditMatchType(ConstString(""))),
                      ],
                      [text("string")],
                    ),
                    el.button(
                      [
                        class(case selection {
                          ConstInteger(_) ->
                            "mr-1 bg-blue-800 text-white rounded border border-blue-600 px-2"
                          _ -> "mr-1 rounded border border-blue-600 px-2"
                        }),
                        event.on_click(EditMatchType(ConstInteger(None))),
                      ],
                      [text("integer")],
                    ),
                    el.button(
                      [
                        class(case selection {
                          ConstBoolean(_) ->
                            "mr-1 bg-blue-800 text-white rounded border border-blue-600 px-2"
                          _ -> "mr-1 rounded border border-blue-600 px-2"
                        }),
                        event.on_click(EditMatchType(ConstBoolean(False))),
                      ],
                      [text("boolean")],
                    ),
                  ]),
                  el.div([], case selection {
                    Variable(var) -> [
                      el.input([
                        class("border my-2"),
                        event.on_input(fn(value) { InputChange(value) }),
                        attribute.value(dynamic.from(var)),
                      ]),
                    ]
                    ConstString(value) -> {
                      let suggestions =
                        case k {
                          0 -> []
                          1 -> db.attribute_suggestions
                          //  value_suggestions are not implemented as there are too many of them
                          2 -> []
                        }
                        |> list.filter(fn(pair) {
                          let #(key, count) = pair
                          string.starts_with(key, value)
                        })

                      [
                        el.input([
                          class("border my-2"),
                          event.on_input(fn(value) { InputChange(value) }),
                          attribute.value(dynamic.from(value)),
                        ]),
                        el.ul(
                          [class("border-l-4 border-blue-800 bg-blue-200")],
                          list.map(list.take(suggestions, 20), fn(pair) {
                            let #(s, count) = pair
                            let matched =
                              string.slice(s, 0, string.length(value))
                            let rest =
                              string.slice(
                                s,
                                string.length(value),
                                string.length(s),
                              )
                            el.li([], [
                              el.button(
                                [
                                  // event.on_click(fn(d) {
                                  //   event.dispatch(InputChange(s))(d)
                                  //   // Is it a bad idea to dispatch multiple events
                                  //   event.dispatch(ReplaceMatch)(d)
                                  // }),
                                  class("flex w-full"),
                                ],
                                [
                                  el.span([class("font-bold")], [text(matched)]),
                                  el.span([], [text(rest)]),
                                  el.span([class("ml-auto mr-2")], [
                                    text(
                                      string.concat([
                                        "(",
                                        int.to_string(count),
                                        ")",
                                      ]),
                                    ),
                                  ]),
                                ],
                              ),
                            ])
                          }),
                        ),
                      ]
                    }

                    ConstInteger(value) -> [
                      el.input([
                        class("border my-2"),
                        event.on_input(fn(value) { InputChange(value) }),
                        attribute.value(
                          dynamic.from(case value {
                            Some(value) -> int.to_string(value)
                            None -> ""
                          }),
                        ),
                        attribute.type_("number"),
                      ]),
                    ]
                    ConstBoolean(value) -> [
                      el.input([
                        class("border my-2"),
                        event.on_click(CheckChange(!value)),
                        attribute.value(dynamic.from("true")),
                        attribute.checked(value),
                        attribute.type_("checkbox"),
                      ]),
                    ]
                  }),
                  el.button(
                    [
                      class(
                        "bg-blue-300 rounded border border-blue-600 px-2 my-2",
                      ),
                      event.on_click(ReplaceMatch),
                    ],
                    [text("Set match")],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ]
    _ -> []
  }
}

fn queries() {
  case hash.decode(get_hash()) {
    Ok(q) -> q
    Error(reason) -> {
      io.debug(reason)
      default_queries()
    }
  }
  |> list.map(fn(q) { #(q, None) })
}

// probably remove these all together
fn default_queries() {
  []
}

fn render_notebook(state, view: serialize.DBView, queries, mode) {
  [
    el.div(
      [
        class(
          "max-w-4xl min-h-full rounded-lg bg-gray-50 mx-auto p-4 text-gray-800 border border-gray-400",
        ),
      ],
      [
        el.header([class("text-center")], [
          el.h1([class("text-2xl")], [text("Queries")]),
          text("database record count: "),
          text(int.to_string(view.triple_count)),
        ]),
        ..list.index_map(queries, render_query(mode, state, view))
        |> list.append([
          el.button(
            [
              event.on_click(AddQuery),
              class("bg-blue-300 rounded py-1 border border-blue-600 px-2 my-2"),
            ],
            [text("Add query")],
          ),
        ])
      ],
    ),
  ]
}

fn render_var(key) {
  el.span([class("text-yellow-600")], [text(string.concat([" ?", key]))])
}

fn match_vars(match) {
  case match {
    query.Constant(_) -> []
    query.Variable(v) -> [v]
  }
}

fn where_vars(where) {
  list.map(where, fn(pattern: query.Pattern) {
    list.flatten([
      match_vars(pattern.0),
      match_vars(pattern.1),
      match_vars(pattern.2),
    ])
  })
  |> list.flatten
  |> list.unique
}

fn render_query(mode, connection, db) {
  fn(i, state) {
    let #(query, cache) = state
    let #(find, where): #(_, List(query.Pattern)) = query

    el.div([class("border-b-2")], [
      el.div([], [
        el.span([class("font-bold")], [text("find: ")]),
        ..list.index_map(find, fn(j, v) {
          el.button([event.on_click(DeleteVariable(i, j))], [render_var(v)])
        })
        |> list.intersperse(text(" "))
        |> list.append(case mode {
          // appended to show plus button inline but potentinaly the div of new values should not be inside
          // the div for the row of values
          ChooseVariable(x) if x == i -> [
            el.div(
              [],
              list.map(
                where_vars(where)
                |> list.filter(fn(w) { !list.contains(find, w) }),
                fn(v) {
                  el.button([event.on_click(SelectVariable(v))], [text(v)])
                },
              )
              |> list.intersperse(text(" ")),
            ),
          ]

          _ -> [
            text(" "),
            el.button(
              [
                class("text-blue-800 font-bold rounded "),
                event.on_click(AddVariable(i)),
              ],
              [text("+")],
            ),
          ]
        })
      ]),
      el.div([], [
        el.span([class("font-bold")], [text("where: ")]),
        el.button(
          [
            event.on_click(AddPattern(i)),
            class("text-blue-800 font-bold rounded "),
          ],
          [text("+")],
        ),
      ]),
      el.div(
        [class("pl-4")],
        list.index_map(where, fn(j, pattern) {
          el.div([], [
            el.span([], [text("[")]),
            render_match(pattern.0, i, j, 0),
            el.span([], [text(" ")]),
            render_match(pattern.1, i, j, 1),
            el.span([], [text(" ")]),
            render_match(pattern.2, i, j, 2),
            el.span([], [text("]")]),
            text(" "),
            el.button(
              [
                class("text-red-200 hover:text-red-800 font-bold rounded "),
                event.on_click(DeletePattern(i, j)),
              ],
              [text("-")],
            ),
          ])
        }),
      ),
      case cache {
        None ->
          el.div([], [
            case connection {
              Ready ->
                el.button(
                  [
                    event.on_click(RunQuery(i)),
                    class(
                      "bg-blue-300 rounded mr-2 py-1 border border-blue-600 px-2 my-2",
                    ),
                  ],
                  [text("Run query")],
                )
              _ ->
                el.button(
                  [
                    attribute.disabled(True),
                    class(
                      "bg-gray-300 rounded mr-2 py-1 border border-gray-600 px-2 my-2",
                    ),
                  ],
                  [text("Run query")],
                )
            },
            el.button(
              [
                event.on_click(DeleteQuery(i)),
                class(
                  "bg-red-300 rounded mr-2 py-1 border border-red-600 px-2 my-2",
                ),
              ],
              [text("Delete query")],
            ),
          ])
        Some(results) -> render_results(find, results, db)
      },
    ])
  }
}

fn render_match(match, i, j, k) {
  el.button([event.on_click(EditMatch(i, j, k))], [
    case match {
      query.Constant(B(value)) ->
        el.span([class("font-bold text-pink-400")], [
          text(case value {
            True -> "true"
            False -> "false"
          }),
        ])
      query.Constant(value) -> text(print_value(value))
      query.Variable(var) -> render_var(var)
    },
  ])
}

fn print_value(value) {
  case value {
    B(False) -> "False"
    B(True) -> "True"
    I(i) -> int.to_string(i)
    L(l) -> "[todo]"
    S(s) -> string.concat(["\"", s, "\""])
  }
}

pub fn render_results(find, results, db) {
  el.details([class("bg-blue-100 p-1 my-2")], [
    el.summary([], [text("rows "), text(int.to_string(list.length(results)))]),
    el.table([class("")], [
      el.thead([], [
        el.tr(
          [],
          list.map(find, fn(var) { el.th([class("font-bold")], [text(var)]) }),
        ),
      ]),
      el.tbody(
        [],
        list.map(results, fn(relation) {
          el.tr(
            [],
            list.map(relation, fn(i) {
              el.td([class("border border-white px-1")], [render_doc(i, db)])
            }),
          )
        }),
      ),
    ]),
  ])
}

fn render_doc(value, db) {
  case value {
    // TODO reenable entity_index but needs codec support
    // I(ref) ->
    //   case map.get(db.entity_index, ref) {
    //     Ok(parts) ->
    //       el.details(
    //         [],
    //         [
    //           el.summary([], [text(int.to_string(ref))]),
    //           el.table(
    //             [],
    //             [
    //               el.tbody(
    //                 [],
    //                 list.map(
    //                   parts,
    //                   fn(triple) {
    //                     el.tr(
    //                       [class("")],
    //                       [
    //                         el.td([class("border px-1")], [text(triple.1)]),
    //                         el.td(
    //                           [class("border px-1")],
    //                           [render_doc(triple.2, db)],
    //                         ),
    //                       ],
    //                     )
    //                   },
    //                 ),
    //               ),
    //             ],
    //           ),
    //         ],
    //       )
    //     Error(Nil) -> text(print_value(I(ref)))
    //   }
    _ -> text(print_value(value))
  }
}
