import datalog/ast
import datalog/browser/app/model.{Model}
import datalog/browser/view/query
import datalog/browser/view/remote
import datalog/browser/view/source
import gleam/dict
import gleam/float
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/result
import gleam/uri
import lustre/attribute.{class}
import lustre/effect
import lustre/element.{text}
import lustre/element/html.{button, div, form, input, p}
import lustre/event.{on_click, on_input}
import midas/browser
import midas/sdk/accu_weather/forecast
import midas/sdk/accu_weather/location
import midas/sdk/google
import midas/sdk/google/calendar
import midas/task as t
import plinth/javascript/storage

pub fn render(model) -> element.Element(model.Wrap) {
  let Model(sections, mode) = model
  div(
    // need outer div for float and absolute
    [class("vstack orange-gradient")],
    // div([class("absolute  bottom-0 left-0 right-0 top-0")], []),
    // div([class("absolute border p-4 bg-white w-full max-w-xl rounded")], [
    //   p([], [text("floating modal")]),
    //   p([], [text("floating modal")]),
    // ]),
    // div(
    //   [
    //     // on_keydown(fn(key) { fn(state) { state + 1 } }),
    //     // attribute.attribute("tabindex", "-1"),
    //     class("vstack w-full max-w-2xl mx-auto"),
    //   ],
    list.flatten(list.index_map(sections, section(mode))),
  )
  // ),
}

fn section(mode) {
  fn(section, index) {
    [
      case section {
        model.Query(q, output) -> {
          let state = case mode {
            model.Editing(target, text, r) if target == index ->
              Some(#(text, r))
            _ -> None
          }
          query.render(index, q, state, output)
        }

        model.Source(relation, headings, table) ->
          source.render(index, relation, headings, table)
        model.Paragraph(content) -> p([], [text(content)])
        model.RemoteSource(request, relation, data) ->
          remote.render(request, relation, data)
      },
      subsection(index, mode),
    ]
  }
}

fn submit_remote(state) {
  let Model(sections, mode) = state
  let assert model.SouceSelection(i, raw) = mode
  let i = i + 1
  let assert Ok(source) = uri.parse(raw)
  let assert Ok(req) = request.from_uri(source)
  let sections = listx.insert_at(sections, i, [model.RemoteSource(req, "", [])])
  let state = Model(sections, model.Viewing)
  // keep request in location for remote
  #(
    state,
    effect.from(fn(dispatch) {
      promise.map_try(model.fetch_source(req), fn(table) {
        dispatch(
          model.Wrap(fn(state) {
            let state = model.update_table(state, i, table)
            #(state, effect.none())
          }),
        )
        Ok(Nil)
      })
      // should I trigger promise from in here or not
      Nil
    }),
  )
}

fn subsection(index, mode) {
  case mode {
    model.SouceSelection(i, raw) if i == index ->
      div([class("border cover")], [
        form(
          [
            event.on("submit", fn(e) {
              event.prevent_default(e)
              Ok(model.Wrap(submit_remote))
            }),
          ],
          [
            input([
              class("border"),
              attribute.value(raw),
              on_input(fn(new) {
                model.Wrap(fn(state) {
                  let Model(sections, mode) = state
                  let assert model.SouceSelection(i, _old) = mode
                  let mode = model.SouceSelection(i, new)
                  #(Model(sections, mode), effect.none())
                })
              }),
            ]),
            button([class("bg-red-500 p-2"), attribute.type_("submit")], [
              text("fetch source"),
            ]),
          ],
        ),
        text("source selection"),
      ])
    // model.GoogleOAuth(i) if i == index -> div([class("border cover")], [])
    // iframe doesnt work
    // iframe([
    //   src(
    //     "https://accounts.google.com/o/oauth2/auth?client_id=419853920596-v2vh33r5h796q8fjvdu5f4ve16t91rkd.apps.googleusercontent.com&response_type=token&redirect_uri=http://localhost:8080&state=123&scope=https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.readonly",
    //   ),
    // ]),
    _ ->
      div([class("hstack tight")], [
        div([class("expand rounded bg-black")], []),
        button(
          [
            class("cursor mx-2 blue-gradient neo-shadow border rounded"),
            on_click(model.Wrap(insert_query(_, index + 1))),
          ],
          [text("new plaintext")],
        ),
        button(
          [
            class("cursor mx-2 blue-gradient neo-shadow border rounded"),
            on_click(model.Wrap(insert_source(_, index + 1))),
          ],
          [text("new source")],
        ),
        button(
          [
            class("cursor mx-2 blue-gradient neo-shadow border rounded"),
            on_click(model.Wrap(fetch_source(_, index))),
          ],
          [text("add source")],
        ),
        button(
          [
            class("cursor mx-2 blue-gradient neo-shadow border rounded"),
            on_click(model.Wrap(google_oauth(_, index + 1))),
          ],
          [text("calendar events")],
        ),
        button(
          [
            class("cursor mx-2 blue-gradient neo-shadow border rounded"),
            on_click(model.Wrap(accu_weather(_, index + 1))),
          ],
          [text("Get weather")],
        ),
        div([class("expand rounded bg-black")], []),
      ])
  }
}

fn insert_query(model, index) {
  let Model(sections, ..) = model
  let new = model.Query([], Ok(dict.new()))
  let sections = listx.insert_at(sections, index, [new])
  #(Model(..model, sections: sections), effect.none())
}

fn insert_source(model, index) {
  let Model(sections, ..) = model
  let new =
    model.Source("Foo", ["bob TODO i don't think used"], [
      [ast.I(2), ast.I(100), ast.S("hey")],
    ])
  let sections = listx.insert_at(sections, index, [new])
  #(Model(..model, sections: sections), effect.none())
}

fn fetch_source(model, index) {
  let mode = model.SouceSelection(index, "")
  #(Model(..model, mode: mode), effect.none())
}

fn google_oauth(model, index) {
  let mode = model.GoogleOAuth(index)
  #(
    Model(..model, mode: mode),
    effect.from(fn(d) {
      use events <- promisex.aside(
        browser.run({
          let app =
            google.App(
              "419853920596-v2vh33r5h796q8fjvdu5f4ve16t91rkd.apps.googleusercontent.com",
              "http://localhost:8080",
            )
          use token <- t.do(
            google.authenticate(app, [
              "https://www.googleapis.com/auth/calendar.events.readonly",
            ]),
          )
          calendar_events(token)
        }),
      )
      case events {
        Ok(events) -> {
          d(
            model.Wrap(fn(state) {
              let Model(sections, mode) = state
              let events =
                list.map(events, fn(e) {
                  let calendar.Event(summary, location, start, end) = e
                  [
                    ast.S(summary),
                    ast.S(option.unwrap(location, "")),
                    ast.S(case start {
                      calendar.Date(s) -> s
                      calendar.Datetime(s) -> s
                    }),
                    ast.S(case end {
                      calendar.Date(s) -> s
                      calendar.Datetime(s) -> s
                    }),
                  ]
                })

              let headings = ["sumamry", "location", "start", "end"]
              let sections =
                listx.insert_at(sections, index, [
                  model.Source("Calendar", headings, events),
                ])
              #(Model(sections, mode), effect.none())
            }),
          )
          Ok(Nil)
        }
        Error(reason) -> {
          io.debug(reason)
          Ok(Nil)
        }
      }
    }),
  )
}

fn calendar_events(token) {
  calendar.list_events(token, "peterhsaxton@gmail.com", "2024-10-01T00:00:00Z")
}

fn accu_weather(model, index) {
  #(
    model,
    effect.from(fn(d) {
      io.debug("weather")
      let assert Ok(s) = storage.local()
      let key = case storage.get_item(s, "ACCU_WEATHER_KEY") {
        Error(Nil) -> panic as "no key"
        Ok(key) -> key
      }

      let task = forecast.five_day_forecast(key, location.stockholm)
      use data <- promisex.aside(browser.run(task))
      use data <- result.map(data)
      d(
        model.Wrap(fn(state) {
          let Model(sections, mode) = state
          let events =
            list.map(data, fn(daily: forecast.DailyForecast) {
              [
                ast.S(daily.date),
                ast.I(float.round(daily.minimum_temperature)),
                ast.I(float.round(daily.maximum_temperature)),
                ast.I(daily.day.precipitation_probability),
                ast.I(daily.night.precipitation_probability),
              ]
            })

          let headings = [
            "date", "maximum", "minumum", "chance of rain (day)",
            "chance of rain (night)",
          ]
          let sections =
            listx.insert_at(sections, index, [
              model.Source("Calendar", headings, events),
            ])
          #(Model(sections, mode), effect.none())
        }),
      )
    }),
  )
  // Ok(Nil)
}
