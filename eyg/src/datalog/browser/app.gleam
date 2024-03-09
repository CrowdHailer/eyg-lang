import gleam/list
import gleam/javascript/promise
import lustre
import lustre/effect
import plinth/browser/window
import datalog/browser/app/model
import datalog/browser/view/page

pub fn run() {
  case window.get_hash() {
    Ok(value) -> {
      Nil
    }
    Error(_) -> {
      let app = lustre.application(init, update, page.render)
      let assert Ok(_) = lustre.start(app, "body > *", Nil)
      Nil
    }
  }
}

fn init(_) {
  let state = model.initial()
  let tasks =
    list.index_map(state.sections, fn(section, index) {
      case section {
        model.RemoteSource(req, _, _) -> {
          let task = fn(dispatch) {
            promise.map(model.fetch_source(req), fn(r) {
              case r {
                Ok(table) ->
                  dispatch(
                    model.Wrap(fn(state) {
                      let state = model.update_table(state, index, table)
                      #(state, effect.none())
                    }),
                  )
                Error(_) -> todo("what went wrong")
              }
            })
            Nil
          }

          [effect.from(task)]
        }
        _ -> []
      }
    })
    |> list.flatten
  #(state, effect.batch(tasks))
}

fn update(model, msg: model.Wrap) {
  let model.Wrap(msg) = msg
  msg(model)
}
