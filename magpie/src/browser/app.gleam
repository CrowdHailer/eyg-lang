import gleam/dynamic.{Dynamic}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import lustre
import lustre/cmd
import lustre/element as el
import lustre/event
import lustre/attribute.{class}
import magpie/store/json
import magpie/store/in_memory.{B, I, L, S}
import magpie/query.{i, s, v}

external fn db() -> Dynamic =
  "../db.mjs" "data"

// At the top to get generic
fn delete_at(items, i) {
  let pre = list.take(items, i)
  let post = list.drop(items, i + 1)
  list.flatten([pre, post])
}

fn map_at(items, i, f) {
  try item = list.at(items, i)
  let pre = list.take(items, i)
  let post = list.drop(items, i + 1)
  Ok(list.flatten([pre, [f(item)], post]))
}

pub fn run() {
  lustre.application(init(), update, render)
  |> lustre.start("#app")
}

pub type MatchSelection {
  Variable(value: String)
  ConstString(value: String)
  ConstInteger(value: Int)
}

pub type Mode {
  OverView
  ChooseVariable(query: Int)
  UpdateMatch(query: Int, pattern: Int, match: Int, selection: MatchSelection)
}

pub type App {
  Loading
  Running(
    db: in_memory.DB,
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
  Index
  RunQuery(Int)
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
}

// choice in edit match, or form submit info in discord

pub fn init() {
  #(
    Loading,
    cmd.from(fn(dispatch) {
      io.debug("starting")
      dispatch(Index)
    }),
  )
}

pub fn update(state, action) {
  case action {
    Index -> {
      assert Ok(triples) = json.decoder()(db())
      let db = in_memory.create_db(list.take(triples, 100))
      io.print("created db")
      #(Running(db, queries(), OverView), cmd.none())
    }
    RunQuery(i) -> {
      io.debug("running")
      assert Running(db, queries, _mode) = state
      assert Ok(q) = list.at(queries, i)
      let #(#(from, where), _cache) = q
      let cache = query.run(from, where, db)
      let pre = list.take(queries, i)
      let post = list.drop(queries, i + 1)
      let queries = list.flatten([pre, [#(#(from, where), Some(cache))], post])
      #(Running(db, queries, OverView), cmd.none())
    }
    AddQuery -> {
      assert Running(db, queries, mode) = state
      let queries = list.append(queries, [#(#([], []), None)])
      #(Running(db, queries, mode), cmd.none())
    }
    DeleteQuery(i) -> {
      assert Running(db, queries, mode) = state
      let queries = delete_at(queries, i)
      #(Running(db, queries, mode), cmd.none())
    }
    AddVariable(i) -> {
      assert Running(db, queries, _) = state
      #(Running(db, queries, ChooseVariable(i)), cmd.none())
    }
    SelectVariable(var) -> {
      assert Running(db, queries, ChooseVariable(i)) = state
      assert Ok(queries) =
        map_at(
          queries,
          i,
          fn(q) {
            let #(#(find, where), _) = q
            let find = [var, ..find]
            #(#(find, where), None)
          },
        )
      #(Running(db, queries, OverView), cmd.none())
    }
    DeleteVariable(i, j) -> {
      assert Running(db, queries, _) = state
      assert Ok(queries) =
        map_at(
          queries,
          i,
          fn(q) {
            let #(#(find, where), _) = q
            #(#(delete_at(find, j), where), None)
          },
        )
      #(Running(db, queries, OverView), cmd.none())
    }
    AddPattern(i) -> {
      assert Running(db, queries, _) = state
      assert Ok(queries) =
        map_at(
          queries,
          i,
          fn(q) {
            let #(#(find, where), _) = q
            let pattern = #(v("_"), v("_"), v("_"))
            let where = [pattern, ..where]
            #(#(find, where), None)
          },
        )
      #(Running(db, queries, OverView), cmd.none())
    }
    EditMatch(i, j, k) -> {
      assert Running(db, queries, _) = state
      assert Ok(#(#(_find, where), _cache)) = list.at(queries, i)
      assert Ok(pattern) = list.at(where, j)
      io.debug(#(i, j, k))

      let match = case k {
        0 -> pattern.0
        1 -> pattern.1
        2 -> pattern.2
      }
      io.debug(match)
      let selection = case match {
        query.Variable(var) -> Variable(var)
        query.Constant(S(value)) -> ConstString(value)
        query.Constant(I(value)) -> ConstInteger(value)
        query.Constant(B(value)) -> todo("booling select")
      }

      let mode = UpdateMatch(i, j, k, selection)
      #(Running(db, queries, mode), cmd.none())
    }
    EditMatchType(selection) -> {
      assert Running(db, queries, UpdateMatch(i, j, k, _)) = state
      #(Running(db, queries, UpdateMatch(i, j, k, selection)), cmd.none())
    }
    ReplaceMatch -> {
      assert Running(db, queries, UpdateMatch(i, j, k, selection)) = state
      let match = case selection {
        Variable(var) -> query.Variable(var)
        ConstString(value) -> query.s(value)
        ConstInteger(value) -> query.i(value)
      }
      assert Ok(queries) =
        map_at(
          queries,
          i,
          fn(q) {
            let #(#(find, where), _cache) = q
            assert Ok(where) =
              map_at(
                where,
                j,
                fn(pattern: query.Pattern) {
                  case k {
                    0 -> #(match, pattern.1, pattern.2)
                    1 -> #(pattern.0, match, pattern.2)
                    2 -> #(pattern.0, pattern.1, match)
                  }
                },
              )
            #(#(find, where), None)
          },
        )
      #(Running(db, queries, OverView), cmd.none())
    }

    DeletePattern(i, j) -> {
      assert Running(db, queries, _) = state
      assert Ok(queries) =
        map_at(
          queries,
          i,
          fn(q) {
            let #(#(find, where), _) = q
            #(#(find, delete_at(where, j)), None)
          },
        )
      #(Running(db, queries, OverView), cmd.none())
    }
    InputChange(new) -> {
      assert Running(db, queries, UpdateMatch(i, j, k, selection)) = state
      let selection = case selection {
        Variable(_) -> Variable(new)
        ConstString(_) -> ConstString(new)
        _ -> todo("input change")
      }
      #(Running(db, queries, UpdateMatch(i, j, k, selection)), cmd.none())
    }
  }
}

pub fn render(state) {
  case state {
    Loading ->
      el.div(
        [
          class(
            "flex flex-col min-h-screen text-center justify-around bg-gray-50 text-xl",
          ),
        ],
        [el.text("loading")],
      )

    Running(db, queries, mode) ->
      el.div(
        [class("bg-gray-200 min-h-screen p-4")],
        list.flatten([render_edit(mode), render_notebook(db, queries, mode)]),
      )
  }
}

fn render_edit(mode) {
  case mode {
    UpdateMatch(_, _, _, selection) -> [
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
                  el.div(
                    [],
                    [el.h2([class("text-xl")], [el.text("update match")])],
                  ),
                  el.div(
                    [],
                    [
                      el.button(
                        [
                          class(
                            "bg-blue-300 rounded border border-blue-600 px-2",
                          ),
                          event.on_click(event.dispatch(EditMatchType(Variable(
                            "x",
                          )))),
                        ],
                        [el.text("variable")],
                      ),
                      el.button(
                        [
                          class(
                            "bg-blue-300 rounded border border-blue-600 px-2",
                          ),
                          event.on_click(event.dispatch(EditMatchType(ConstString(
                            "",
                          )))),
                        ],
                        [el.text("string")],
                      ),
                      el.button(
                        [
                          class(
                            "bg-blue-300 rounded border border-blue-600 px-2",
                          ),
                          event.on_click(event.dispatch(EditMatchType(ConstInteger(
                            0,
                          )))),
                        ],
                        [el.text("integer")],
                      ),
                    ],
                  ),
                  el.div(
                    [],
                    [
                      case selection {
                        Variable(var) ->
                          el.input([
                            class("border mx-2"),
                            event.on_input(fn(value, d) {
                              event.dispatch(InputChange(value))(d)
                            }),
                            attribute.value(dynamic.from(var)),
                          ])
                        ConstString(value) ->
                          el.input([
                            class("border mx-2"),
                            event.on_input(fn(value, d) {
                              event.dispatch(InputChange(value))(d)
                            }),
                            attribute.value(dynamic.from(value)),
                          ])
                        ConstInteger(value) ->
                          el.input([
                            class("border mx-2"),
                            event.on_input(fn(value, d) {
                              event.dispatch(InputChange(value))(d)
                            }),
                            attribute.value(dynamic.from(int.to_string(value))),
                          ])
                      },
                    ],
                  ),
                  el.button(
                    [
                      class("bg-blue-300 rounded border border-blue-600 px-2"),
                      event.on_click(event.dispatch(ReplaceMatch)),
                    ],
                    [el.text("Set match")],
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

pub fn queries() {
  [
    #(
      #(
        ["version"],
        [
          #(v("values"), s("version"), v("version")),
          #(v("values"), s("driver"), s("litmus")),
        ],
      ),
      None,
    ),
    #(
      #(
        ["driver", "version"],
        [
          #(v("values"), s("driver"), v("driver")),
          #(v("values"), s("version"), v("version")),
          #(v("values"), s("replicaCount"), i(0)),
        ],
      ),
      None,
    ),
  ]
}

fn render_notebook(db, queries, mode) {
  [
    el.div(
      [
        class(
          "max-w-4xl min-h-full rounded-lg bg-gray-50 mx-auto p-4 text-gray-800 border border-gray-400",
        ),
      ],
      [
        el.header(
          [class("text-center")],
          [
            el.h1([class("text-2xl")], [el.text("Queries")]),
            el.text("database record count: "),
            el.text(int.to_string(list.length(db.triples))),
          ],
        ),
        ..list.index_map(queries, render_query(mode))
        |> list.append([
          el.button(
            [
              event.on_click(event.dispatch(AddQuery)),
              class("bg-blue-300 rounded py-1 border border-blue-600 px-2 my-2"),
            ],
            [el.text("Add query")],
          ),
        ])
      ],
    ),
  ]
}

fn render_var(key) {
  el.span([class("text-yellow-600")], [el.text(string.concat([" ?", key]))])
}

fn match_vars(match) {
  case match {
    query.Constant(_) -> []
    query.Variable(v) -> [v]
  }
}

fn where_vars(where) {
  list.map(
    where,
    fn(pattern: query.Pattern) {
      list.flatten([
        match_vars(pattern.0),
        match_vars(pattern.1),
        match_vars(pattern.2),
      ])
    },
  )
  |> list.flatten
  |> list.unique
}

fn render_query(mode) {
  fn(i, state) {
    let #(query, cache) = state
    let #(find, where): #(_, List(query.Pattern)) = query

    el.div(
      [class("border-b-2")],
      [
        el.div(
          [],
          [
            el.span([class("font-bold")], [el.text("find: ")]),
            ..list.index_map(
              find,
              fn(j, v) {
                el.button(
                  [event.on_click(event.dispatch(DeleteVariable(i, j)))],
                  [render_var(v)],
                )
              },
            )
            |> list.intersperse(el.text(" "))
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
                      el.button(
                        [event.on_click(event.dispatch(SelectVariable(v)))],
                        [el.text(v)],
                      )
                    },
                  )
                  |> list.intersperse(el.text(" ")),
                ),
              ]

              _ -> [
                el.text(" "),
                el.button(
                  [
                    class("text-blue-800 font-bold rounded "),
                    event.on_click(event.dispatch(AddVariable(i))),
                  ],
                  [el.text("+")],
                ),
              ]
            })
          ],
        ),
        el.div(
          [],
          [
            el.span([class("font-bold")], [el.text("where: ")]),
            el.button(
              [
                event.on_click(event.dispatch(AddPattern(i))),
                class("text-blue-800 font-bold rounded "),
              ],
              [el.text("+")],
            ),
          ],
        ),
        el.div(
          [class("pl-4")],
          list.index_map(
            where,
            fn(j, pattern) {
              el.div(
                [],
                [
                  el.span([], [el.text("[")]),
                  render_match(pattern.0, i, j, 0),
                  el.span([], [el.text(" ")]),
                  render_match(pattern.1, i, j, 1),
                  el.span([], [el.text(" ")]),
                  render_match(pattern.2, i, j, 2),
                  el.span([], [el.text("]")]),
                  el.text(" "),
                  el.button(
                    [
                      class(
                        "text-red-200 hover:text-red-800 font-bold rounded ",
                      ),
                      event.on_click(event.dispatch(DeletePattern(i, j))),
                    ],
                    [el.text("-")],
                  ),
                ],
              )
            },
          ),
        ),
        case cache {
          None ->
            el.div(
              [],
              [
                el.button(
                  [
                    event.on_click(event.dispatch(RunQuery(i))),
                    class(
                      "bg-blue-300 rounded mr-2 py-1 border border-blue-600 px-2 my-2",
                    ),
                  ],
                  [el.text("Run query")],
                ),
                el.button(
                  [
                    event.on_click(event.dispatch(DeleteQuery(i))),
                    class(
                      "bg-red-300 rounded mr-2 py-1 border border-red-600 px-2 my-2",
                    ),
                  ],
                  [el.text("Delete query")],
                ),
              ],
            )
          Some(results) -> render_results(find, results)
        },
      ],
    )
  }
}

fn render_match(match, i, j, k) {
  el.button(
    [event.on_click(event.dispatch(EditMatch(i, j, k)))],
    [
      case match {
        query.Constant(value) -> el.text(print_value(value))
        query.Variable(var) -> render_var(var)
      },
    ],
  )
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

pub fn render_results(find, results) {
  el.table(
    [class("my-2")],
    [
      el.thead(
        [],
        [
          el.tr(
            [],
            list.map(
              find,
              fn(var) { el.th([class("font-bold")], [el.text(var)]) },
            ),
          ),
        ],
      ),
      el.tbody(
        [],
        list.map(
          results,
          fn(relation) {
            el.tr(
              [],
              list.map(
                relation,
                fn(i) {
                  el.td([class("border px-1")], [el.text(print_value(i))])
                },
              ),
            )
          },
        ),
      ),
    ],
  )
}
