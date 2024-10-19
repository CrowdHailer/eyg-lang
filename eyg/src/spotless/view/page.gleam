import drafting/view/page
import drafting/view/picker
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic
import eyg/shell/buffer
import eyg/website/components/output
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{none, text}
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/lustre/render
import morph/projection as p
import plinth/javascript/console
import spotless/state

pub fn render_previous(previous) {
  list.map(list.reverse(previous), fn(p) {
    let #(value, prog) = p
    h.div([a.class("w-full max-w-4xl mt-2 py-1 bg-white shadow-xl rounded")], [
      h.div(
        [a.class("px-3 whitespace-nowrap overflow-auto")],
        render.statements(prog),
      ),
      case value {
        Some(value) ->
          h.div([a.class("mx-3 pt-1 border-t max-h-60 overflow-auto")], [
            output.render(value),
          ])
        None -> none()
      },
    ])
  })
}

pub fn do_render(
  previous,
  context,
  current,
  executing,
  examples,
  // These message arguments not needed if we have better components but interrupt currently is mixed in with buffer messages
  buffer_message: fn(buffer.Message) -> a,
  interrupt_message: fn() -> a,
  load_message: fn(p.Projection) -> a,
) -> element.Element(a) {
  // containter for relative positioning
  h.div([a.class("hstack bg-gray-100 font-mono p-6 gap-6")], [
    h.div([a.class("vstack flex-grow max-w-4xl")], [
      h.header([], [
        h.h1([a.class("text-2xl")], [text("EYG shell")]),
        h.h1([a.class("font-bold")], [text("automate anything")]),
      ]),
      ..render_previous(previous)
      |> list.append([
        h.div(
          [
            a.class(
              "w-full max-w-4xl mt-2 bg-white shadow-xl rounded overflow-hidden",
            ),
          ],
          [
            // Cant paste to input label
            h.div(
              [
                a.class(
                  "px-3 py-1 outline-none whitespace-nowrap overflow-auto",
                ),
                a.attribute("tabindex", "0"),
                event.on_keydown(buffer.KeyDown),
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
            )
              |> element.map(buffer_message),
            ..case executing {
              state.Editing(buffer.Command(None)) -> [
                h.div([a.class("w-full orange-gradient text-white")], [
                  h.div([], []),
                  ..list.map(
                    analysis.type_errors(analysis.analyse(
                      current,
                      context,
                      isomorphic.Empty,
                    )),
                    fn(e) {
                      let #(path, reason) = e
                      case reason {
                        error.SameTail(_, _) -> {
                          io.debug("error i still dont understand")
                          element.none()
                        }
                        _ ->
                          h.div([a.class("px-3")], [
                            h.a([event.on_click(buffer.JumpTo(path))], [
                              text(page.path_to_string(path)),
                            ]),
                            text(" "),
                            text(debug.reason(reason)),
                          ])
                          |> element.map(buffer_message)
                      }
                    },
                  )
                ]),
              ]
              state.Editing(buffer.EditInteger(value, _)) ->
                overlay([
                  page.integer_input(value)
                  |> element.map(buffer_message),
                ])
              state.Editing(buffer.EditText(value, _)) ->
                overlay([
                  page.string_input(value)
                  |> element.map(buffer_message),
                ])
              state.Editing(buffer.Pick(picker, _)) ->
                overlay([
                  picker.render(picker, buffer.UpdatePicker)
                  |> element.map(buffer_message),
                ])
              state.Running -> [
                h.div([a.class("w-full green-gradient px-3 flex")], [
                  h.span([a.class("flex-grow")], [text("running ...")]),
                  h.button([event.on_click(interrupt_message())], [
                    text("Interrupt"),
                  ]),
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
        case p.blank(current) {
          True ->
            h.div([a.class("max-w-4xl w-full px-3 mt-2")], [
              h.div([a.class("font-bold")], [text("Try:")]),
              h.ul(
                [a.class("leading-snug list-disc list-inside text-gray-500")],
                list.map(examples, fn(example) {
                  let #(source, description) = example
                  h.li([a.class(""), event.on_click(load_message(source))], [
                    text(description),
                  ])
                }),
              ),
            ])
          False ->
            h.div([a.class("truncate max-w-4xl w-full text-right px-3")], [
              text(case analysis.type_at(current, context, isomorphic.Empty) {
                Ok(t) -> debug.mono(t)
                Error(_) -> "no type info"
              }),
            ])
        },
      ])
    ]),
    h.div([a.class("border bg-white rounded p-2 shadow-xl")], [
      h.h1([a.class("text-xl font-bold")], [text("commands")]),
      page.key_references(),
    ]),
  ])
}

pub fn render(app) {
  let state.State(previous, _env, context, current, executing) = app
  do_render(
    previous,
    context,
    current,
    executing,
    [
      #(state.weather_example(), "get the weather at your location"),
      #(state.netliy_sites_example(), "list all of my sites on Netlify"),
      #(state.wordcount_example(), "count all the words in a file"),
    ],
    state.Buffer,
    fn() { state.Interrupt },
    state.Loaded,
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
