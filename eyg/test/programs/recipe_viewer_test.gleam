import gleam/io
import gleam/string
import eyg/ast/encode
import eyg/ast/expression as e
import eyg/interpreter/interpreter as r
import eyg/interpreter/effectful
// TODO need an effectful version that allows us to access stuff here
import eyg/interpreter/tail_call
import cli

// ------- Move

pub fn fetching_a_recipe_test() {
  let program = e.access(cli.load(), "recipe")
  // TODO we can assert that the type is of the correct value
  assert Ok(term) = effectful.eval(program)

  // TODO make request a real request
  let request = r.Tuple([])
  assert Ok(r.Effect("HTTP", request, cont)) =
    tail_call.eval_call(term, request)
  assert r.Tagged("Get", r.Binary(url)) = request
  io.debug(url)
  assert Ok(r.Binary(content)) = cont(r.Binary("stuff"))
  io.debug(content)
  todo("THis is the test")
}
