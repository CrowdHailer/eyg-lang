import gleam/io
import gleam/option.{None, Some}
import eygir/expression as e
import morph/transform as morph
import gleeunit/should

pub fn single_term_test() {
  let source = e.Binary("original")
  assert Ok(m) = morph.prepare([], source)

  // Nav
  assert None = morph.up(m)
  assert None = morph.down(m)
  assert None = morph.left(m)
  assert None = morph.right(m)

  // blank
  // TODO always available when in expressions
  assert Some(transform) = morph.line_above(m)
  transform("foo")
  |> should.equal(e.Let("foo", e.Vacant, source))

  // TODO manage without line below
  // Drags left right become Add fields
  // create
  assert Some(transform) = morph.variable(m)
  transform("x")
  |> should.equal(e.Variable("x"))

  assert Some(transform) = morph.function(m)
  transform("x")
  |> should.equal(e.Lambda("x", source))

  assert Some(transform) = morph.call(m)
  transform()
  |> should.equal(e.Apply(source, e.Vacant))

  assert Some(transform) = morph.call_with(m)
  transform()
  |> should.equal(e.Apply(e.Vacant, source))

  // Line above and assign are close
  assert Some(transform) = morph.assign(m)
  transform("x")
  |> should.equal(e.Let("x", source, e.Vacant))

  // primitive
  assert Some(transform) = morph.string(m)
  transform("foo")
  |> should.equal(e.Binary("foo"))

  // record on hole is fix
  // record on anything else is extended
  // reality is only variable works
  // TODO fixed constructor behaviour below i.e. record on stuff
  //   record of a foo alway wraps
  //   assert Some(f) = morph.record(m)
  //   TODO what does record doo 
  // R on var(x) -> {foo = var(x)} or {foo = blank, var(X)}
  // can have add field work on plain terms but is it explicit and does it confuse inside matches
  // r add field if blank it becomes the tail
  // e is line above on let statement but nesting on term. i don't mind being precise
  // Select & tag need to decide if call call? no for now TODO
  assert Some(transform) = morph.select(m)
  transform("name")
  |> should.equal(e.Apply(e.Select("name"), source))

  assert Some(transform) = morph.tag(m)
  transform("Ok")
  |> should.equal(e.Apply(e.Tag("Ok"), source))

  assert Some(transform) = morph.perform(m)
  transform("Log")
  |> should.equal(e.Apply(e.Perform("Log"), source))

  // delete
  assert None = morph.delete(m)

  // unwrap
  assert None = morph.unwrap(m)
  // paste
}

pub fn assignmet_block_test() {
  let source = e.Let("x", e.Binary(""), e.Let("y", e.Integer(0), e.Binary("")))

  // focused on whole let
  assert Ok(m) = morph.prepare([2], source)
  //   todo
  assert Some([]) = morph.up(m)
  assert Some([2, 2]) = morph.down(m)
  assert None = morph.left(m)
  assert None = morph.right(m)

  // create
  assert Some(transform) = morph.variable(m)
  e.Let("x", e.Binary(""), e.Let("y", e.Variable("x"), e.Binary("")))
  |> should.equal(transform("x"), _)

  // delete
  assert Some(transform) = morph.delete(m)
  e.Let("x", e.Binary(""), e.Let("y", e.Vacant, e.Binary("")))
  |> should.equal(transform(), _)
  // TODO delete on row already on vacant
}

// could have at least one e.Let as the minimum block no special end cases
// would also need inside function which has single block
// e assignment is line above or below

pub fn call_test() {
  let source = e.Apply(e.Variable("f"), e.Binary("foo"))

  assert Ok(m) = morph.prepare([0], source)

  // Nav
  //     assert Some([]) = morph.up(m)
  //   assert Some([2, 2]) = morph.down(m)
  assert None = morph.left(m)
  assert Some([1]) = morph.right(m)

  assert Some([]) = morph.increase(m)
  // delete
  assert Some(transform) = morph.delete(m)
  e.Apply(e.Vacant, e.Binary("foo"))
  |> should.equal(transform(), _)

  // unwrap
  assert Some(transform) = morph.unwrap(m)
  e.Variable("f")
  |> should.equal(transform(), _)
}
// Lookup types on the outside, look up envs on the outside
// you might want to e assign a let already

// drag left rigt needed for tuple or arrays, arrays needed if no tuples and providers
