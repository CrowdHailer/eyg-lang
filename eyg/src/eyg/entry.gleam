import gleam/io
import gleam/string
import eyg/ast/encode
import eyg/ast/expression as e
import eyg/interpreter/effectful
// TODO need an effectful version that allows us to access stuff here
import eyg/interpreter/tail_call
import gleam/javascript/array
import eyg/interpreter/interpreter as r
import eyg/analysis
import eyg/typer
import eyg/typer/monotype as t
import eyg/editor/editor

fn update(page, interrupt, display, on_click) { 
    
    io.debug(page)
    display(page)

 }


fn b(args) { 
    Ok(r.Binary("done"))
 }
// uses default builtin that need moving out of effectful
// has an entry point key should eventually be a hash
// maybe rename interpret standard
// builtin is always the same but env things are passed in
// All the runtime stuff is in gleam terms
// TODO are there any gleam helpers to turn tuples into things
pub fn interpret_client(source, key, display, on_click) {
    io.debug("hooo")
    let init = e.access(e.access(source, key), "init")
    io.debug(init)
  let #(typed, typer) = analysis.infer(init, t.Unbound(-1), [])
  io.debug("---- typed")
  let #(xtyped, typer) = typer.expand_providers(typed, typer, [])
//   assert Ok(term) = effectful.eval(editor.untype(xtyped))
//   io.debug(term)
  |> io.debug
//   effectful.eval_call(r.BuiltinFn(b), term, effectful.real_log)
//   |> io.debug
// //   TODO make an AST the requires rendering
//   term
}