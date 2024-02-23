import gleam/io
import eyg/parse/lexer
import eyg/parse/parser
import eyg/analysis/type_/isomorphic as t
import eyg/analysis/inference/levels_j/contextual as j
import eygir/annotated as a
import eyg/analysis/type_/binding
import eyg/compile/ir
import eyg/compile/js
import gleeunit/should

fn parse(src) {
  src
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
}

pub fn alpha_normalisation_let_test() {
  "let x =
    let x = 2
    x
  x"
  |> parse
  |> ir.alpha()
  |> should.equal(
    #(
      a.Let(
        "$a0",
        #(
          a.Let(
            "$a1",
            #(a.Integer(2), #(21, 22)),
            #(a.Variable("$a1"), #(27, 28)),
          ),
          #(13, 28),
        ),
        #(a.Variable("$a0"), #(31, 32)),
      ),
      #(0, 32),
    ),
  )
}

pub fn alpha_normalisation_apply_test() {
  "(x) -> { 5 }(7)"
  |> parse
  |> ir.alpha()
  |> should.equal(
    #(
      a.Apply(
        #(a.Lambda("$a1", #(a.Integer(5), #(9, 10))), #(0, 12)),
        #(a.Integer(7), #(13, 14)),
      ),
      #(0, 15),
    ),
  )
}

fn do_resolve(return) {
  let #(exp, bindings) = return
  a.map_annotation(exp, fn(types) {
    let #(_, _, effect, _) = types
    binding.resolve(effect, bindings)
  })
}

pub fn effect_lifting_test() {
  "[perform Foo(3)]"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.k()
  |> io.debug
  |> ir.unnest
  |> a.drop_annotation()
  |> io.debug
  //   let source = #(a.Str("s"), t.Empty)
  //   ir.k(source, True)
  //   |> should.equal(source)
}

pub fn effect_not_lifting_test() {
  "perform Foo([2])"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.k()
  |> io.debug
  |> ir.unnest
  |> a.drop_annotation()
  |> io.debug
  //   let source = #(a.Str("s"), t.Empty)
  //   ir.k(source, True)
  //   |> should.equal(source)
}

// TODO just print all the javascript in textual

pub fn compile_test() {
  "[1,2,3]"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> io.debug
  |> js.render()
  |> io.debug

  "let x = [2]
  x"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> io.debug
  |> js.render()
  |> io.println

  // unnesting takes care of nested let
  "let x = [let y = 5 y]
  x"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> js.render()
  |> io.println

  "({x,y}) -> { 5 }"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> js.render()
  |> io.println

  "{ x, y: let z = 5 z }"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> js.render()
  |> io.println

  // TODO parse else branch
  "match Ok(2) {
    Ok(a) -> { a }
    Error foo
  }"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> js.render()
  |> io.println

  "match Ok(2) {
    Ok(a) -> { a }
    (x) -> { 0 }
  }"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> js.render()
  |> io.println

  "{a: 1, ..let x = {a: 2} x}"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> js.render()
  |> io.println

  "{a: 1, ..(x) -> { {} }}"
  |> parse
  |> a.drop_annotation()
  |> j.infer(t.Empty, 0, j.new_state())
  |> do_resolve()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> a.drop_annotation()
  |> js.render()
  |> io.println
}
// TODO test with eval