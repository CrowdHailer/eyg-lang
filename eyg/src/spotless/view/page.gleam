import drafting/state as buffer
import drafting/view/page
import drafting/view/picker
import eyg/analysis/type_/binding/debug
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/stringx
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/lustre/render
import plinth/javascript/console
import spotless/state
import spotless/view/output

pub fn render(app) {
  let state.State(previous, _env, context, current, executing) = app
  // containter for relative positioning
  h.div(
    [a.class("vstack bg-gray-100 font-mono")],
    list.map(list.reverse(previous), fn(p) {
      let #(value, prog) = p
      h.div([a.class("w-full max-w-3xl mt-2 bg-white shadow-xl rounded")], [
        h.div([a.class("px-3")], render.statements(prog)),
        h.div([a.class("px-3 border-t")], case value {
          Some(value) -> [output.render(value)]
          None -> []
        }),
      ])
    })
      |> list.append([
      h.div(
        [
          a.class(
            "w-full max-w-3xl mt-2 bg-white shadow-xl rounded overflow-hidden",
          ),
        ],
        [
          // Cant paste to input label
          h.div(
            [
              a.class("px-3 outline-none"),
              a.attribute("tabindex", "0"),
              event.on_keydown(state.KeyDown),
              // content editable has cursor moving separatly to highlighted and focused node
              // a.attribute("contenteditable", ""),
              event.on("paste", fn(event) {
                event.prevent_default(event)
                console.log(event)
                Error([])
              }),
              // event.on("beforeinput", fn(event) {
              //   event.prevent_default(event)
              //   Error([])
              // }),
              a.id("code"),
            ],
            [render.projection(current, False)],
          ),
          ..case executing {
            state.Editing(buffer.Command(None)) -> [
              h.div([a.class("w-full orange-gradient text-white")], [
                h.div([], []),
                ..list.map(
                  analysis.type_errors(analysis.analyse(current, context)),
                  fn(e) {
                    let #(path, reason) = e
                    // analysis reverses the paths to correct order
                    // let path = list.reverse(path)
                    h.div([a.class("px-3")], [
                      h.a([event.on_click(state.JumpTo(path))], [
                        text(page.path_to_string(path)),
                      ]),
                      text(" "),
                      text(reason),
                    ])
                  },
                )
              ]),
            ]
            state.Editing(buffer.EditInteger(value, _)) ->
              overlay([
                page.integer_input(value)
                |> element.map(state.Buffer),
              ])
            state.Editing(buffer.EditText(value, _)) ->
              overlay([
                page.string_input(value)
                |> element.map(state.Buffer),
              ])
            state.Editing(buffer.Pick(picker, _)) ->
              overlay([picker.render(picker, state.UpdatePicker)])
            state.Running -> [
              h.div([a.class("w-full green-gradient px-3 flex")], [
                h.span([a.class("flex-grow")], [text("running ...")]),
                h.button([event.on_click(state.Interrupt)], [text("Interrupt")]),
              ]),
            ]
            state.Editing(buffer.Command(Some(reason))) -> [
              h.div([a.class("w-full orange-gradient text-white px-3")], [
                text(fail_message(reason)),
              ]),
            ]
            state.Failed(reason) -> [
              h.div([a.class("w-full orange-gradient text-white px-3")], [
                text(reason),
              ]),
            ]
          }
        ],
      ),
      h.div([a.class("truncate max-w-3xl w-full text-right px-3")], [
        text(case analysis.type_at(current, context) {
          Ok(t) -> debug.render_type(t)
          Error(_) -> "no type info"
        }),
      ]),
    ]),
  )
}

fn overlay(content) {
  [
    h.div(
      [],
      // a.class(
      //   "bg-black text-white border-black mx-auto max-w-2xl border w-full rounded",
      // ),
      content,
    ),
  ]
}

pub fn fail_message(reason) {
  case reason {
    buffer.NoKeyBinding(key) ->
      string.concat(["No action bound for key '", key, "'"])
    buffer.ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
  }
}
