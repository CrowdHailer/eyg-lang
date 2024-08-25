import drafting/view/picker
import eyg/shell/buffer
import gleam/io
import gleam/listx
import gleam/option.{Some}
import gleeunit/should
import morph/analysis

fn update(state, message) {
  let context = analysis.empty_environment()
  let effects = []
  let state = buffer.update(state, message, context, effects)
  case state.1 {
    buffer.Command(Some(reason)) -> Error(reason)
    _ -> Ok(state)
  }
}

pub fn hashes_listed_test() {
  let ref = "habc"
  let state =
    buffer.empty()
    |> update(buffer.KeyDown("#"))
    // |> should.be_ok
    // |> update(buffer.UpdateInput(ref))
    |> should.be_ok
    // |> update(buffer.Submit)
    |> update(buffer.UpdatePicker(picker.Decided(ref)))
    |> should.be_ok

  buffer.references(state)
  |> should.equal([ref])
}

pub fn function_parameters_in_scope_test() {
  let state =
    buffer.empty()
    |> update(buffer.KeyDown("f"))
    |> should.be_ok
    // |> update(buffer.UpdateInput("x"))
    // |> update(buffer.UpdatePicker(picker.Updated()))
    // |> should.be_ok
    |> update(buffer.UpdatePicker(picker.Decided("x")))
    |> io.debug
    |> should.be_ok
    |> update(buffer.KeyDown("v"))
    |> should.be_ok

  let assert buffer.Pick(picker, _) = state.1
  listx.keys(picker.suggestions)
  |> should.equal(["x"])
}
