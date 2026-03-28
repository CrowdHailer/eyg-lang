import gleam/option.{None, Some}
import gleeunit/should
import morph/editable as e
import morph/projection as p

fn should_equal(given, expected) {
  should.equal(given, expected)
  given
}

pub fn block_test() {
  let first = #(e.Bind("i"), e.Integer(10))
  let second = #(e.Destructure([#("foo", "y")]), e.Record([], None))
  let source = e.Block([first, second], e.Vacant, False)

  let path = [0]
  p.focus_at(source, path)
  |> should_equal(
    #(
      p.Assign(
        p.AssignStatement(e.Bind("i")),
        e.Integer(10),
        [],
        [second],
        e.Vacant,
      ),
      [],
    ),
  )
  |> p.path
  |> should_equal(path)

  let path = [0, 0]
  p.focus_at(source, path)
  |> should_equal(
    #(
      p.Assign(
        p.AssignPattern(e.Bind("i")),
        e.Integer(10),
        [],
        [second],
        e.Vacant,
      ),
      [],
    ),
  )
  |> p.path
  |> should_equal(path)

  let path = [0, 1]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Integer(10)), [p.BlockValue(e.Bind("i"), [], [second], e.Vacant)]),
  )
  |> p.path
  |> should_equal(path)

  let path = [1, 0, 0]
  p.focus_at(source, path)
  |> should_equal(
    #(
      p.Assign(
        p.AssignField("foo", "y", [], []),
        e.Record([], None),
        [first],
        [],
        e.Vacant,
      ),
      [],
    ),
  )
  |> p.path
  |> should_equal(path)
  let path = [1, 0, 1]
  p.focus_at(source, path)
  |> should_equal(
    #(
      p.Assign(
        p.AssignBind("foo", "y", [], []),
        e.Record([], None),
        [first],
        [],
        e.Vacant,
      ),
      [],
    ),
  )
  |> p.path
  |> should_equal(path)
}

pub fn function_test() {
  let source =
    e.Function([e.Bind("x"), e.Destructure([#("foo", "y")])], e.String("body"))

  let path = [0]
  p.focus_at(source, path)
  |> should_equal(
    #(
      p.FnParam(
        p.AssignPattern(e.Bind("x")),
        [],
        [e.Destructure([#("foo", "y")])],
        e.String("body"),
      ),
      [],
    ),
  )
  |> p.path
  |> should_equal(path)

  let path = [1]
  p.focus_at(source, path)
  |> should_equal(
    #(
      p.FnParam(
        p.AssignPattern(e.Destructure([#("foo", "y")])),
        [e.Bind("x")],
        [],
        e.String("body"),
      ),
      [],
    ),
  )
  |> p.path
  |> should_equal(path)

  let path = [2]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.String("body")), [
      p.Body([e.Bind("x"), e.Destructure([#("foo", "y")])]),
    ]),
  )
  |> p.path
  |> should_equal(path)
}

pub fn function_destructure_test() {
  let source =
    e.Function(
      [e.Destructure([#("foo", "x"), #("bar", "y")])],
      e.String("body"),
    )

  let path = [0, 0]
  p.focus_at(source, path)
  |> should_equal({
    let focus = p.AssignField("foo", "x", [], [#("bar", "y")])
    #(p.FnParam(focus, [], [], e.String("body")), [])
  })
  |> p.path
  |> should_equal(path)

  let path = [0, 1]
  p.focus_at(source, path)
  |> should_equal({
    let focus = p.AssignBind("foo", "x", [], [#("bar", "y")])
    #(p.FnParam(focus, [], [], e.String("body")), [])
  })
  |> p.path
  |> should_equal(path)

  let path = [0, 2]
  p.focus_at(source, path)
  |> should_equal({
    let focus = p.AssignField("bar", "y", [#("foo", "x")], [])
    #(p.FnParam(focus, [], [], e.String("body")), [])
  })
  |> p.path
  |> should_equal(path)

  let path = [0, 3]
  p.focus_at(source, path)
  |> should_equal({
    let focus = p.AssignBind("bar", "y", [#("foo", "x")], [])
    #(p.FnParam(focus, [], [], e.String("body")), [])
  })
  |> p.path
  |> should_equal(path)
}

pub fn nested_function_test() {
  let source =
    e.Function(
      [e.Bind("x")],
      e.Function(
        [e.Bind("a"), e.Bind("b")],
        e.Call(e.Variable("f"), [e.Variable("s")]),
      ),
    )

  let path = [1, 2, 0]
  p.focus_at(source, path)
  |> should_equal({
    let zoom = [
      p.CallFn([e.Variable("s")]),
      p.Body([e.Bind("a"), e.Bind("b")]),
      p.Body([e.Bind("x")]),
    ]
    #(p.Exp(e.Variable("f")), zoom)
  })
  |> p.path
  |> should_equal(path)

  source
  |> e.to_annotated([])
}

pub fn function_body_test() {
  let source =
    e.Function(
      [e.Bind("x")],
      e.Block([#(e.Bind("s"), e.String("first"))], e.Variable("s"), True),
    )

  let path = [1]
  p.focus_at(source, path)
  |> should_equal(
    #(
      p.Exp(e.Block([#(e.Bind("s"), e.String("first"))], e.Variable("s"), True)),
      [p.Body([e.Bind("x")])],
    ),
  )
  |> p.path
  |> should_equal(path)

  let path = [1, 1]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Variable("s")), [
      p.BlockTail([#(e.Bind("s"), e.String("first"))]),
      p.Body([e.Bind("x")]),
    ]),
  )
  |> p.path
  |> should_equal(path)
}

pub fn list_test() {
  let source = e.List([e.Integer(1), e.Integer(2)], Some(e.Variable("tail")))

  let path = [0]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Integer(1)), [
      p.ListItem([], [e.Integer(2)], Some(e.Variable("tail"))),
    ]),
  )
  |> p.path
  |> should_equal(path)

  let path = [1]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Integer(2)), [
      p.ListItem([e.Integer(1)], [], Some(e.Variable("tail"))),
    ]),
  )
  |> p.path
  |> should_equal(path)

  let path = [2]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Variable("tail")), [p.ListTail([e.Integer(1), e.Integer(2)])]),
  )
  |> p.path
  |> should_equal(path)
}

pub fn record_test() {
  let source = e.Record([#("foo", e.Integer(1)), #("bar", e.Integer(2))], None)

  let path = [0]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Label("foo", e.Integer(1), [], [#("bar", e.Integer(2))], p.Record), []),
  )
  |> p.path
  |> should_equal(path)

  let path = [1]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Integer(1)), [
      p.RecordValue("foo", [], [#("bar", e.Integer(2))], p.Record),
    ]),
  )
  |> p.path
  |> should_equal(path)

  let path = [2]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Label("bar", e.Integer(2), [#("foo", e.Integer(1))], [], p.Record), []),
  )
  |> p.path
  |> should_equal(path)

  let path = [3]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Integer(2)), [
      p.RecordValue("bar", [#("foo", e.Integer(1))], [], p.Record),
    ]),
  )
  |> p.path
  |> should_equal(path)
}

pub fn select_test() {
  let source = e.Select(e.Variable("x"), "foo")

  let path = [0]
  p.focus_at(source, path)
  |> should_equal(#(p.Exp(e.Variable("x")), [p.SelectValue("foo")]))
  |> p.path
  |> should_equal(path)

  let path = [1]
  p.focus_at(source, path)
  |> should_equal(#(p.Select("foo", e.Variable("x")), []))
  |> p.path
  |> should_equal(path)
}

pub fn overwrite_test() {
  let source = e.Record([#("foo", e.Integer(1))], Some(e.Variable("x")))

  let path = [0]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Label("foo", e.Integer(1), [], [], p.Overwrite(e.Variable("x"))), []),
  )
  |> p.path
  |> should_equal(path)

  let path = [1]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Integer(1)), [
      p.RecordValue("foo", [], [], p.Overwrite(e.Variable("x"))),
    ]),
  )
  |> p.path
  |> should_equal(path)

  let path = [2]
  p.focus_at(source, path)
  |> should_equal(
    #(p.Exp(e.Variable("x")), [p.OverwriteTail([#("foo", e.Integer(1))])]),
  )
  |> p.path
  |> should_equal(path)
}

pub fn match_test() {
  let source =
    e.Case(e.Variable("result"), [#("Ok", e.Integer(1))], Some(e.Variable("x")))

  let path = [1]
  p.do_focus_at(source, path, [])
  |> should.be_ok()
  |> should_equal(
    #(
      p.Match(
        e.Variable("result"),
        "Ok",
        e.Integer(1),
        [],
        [],
        Some(e.Variable("x")),
      ),
      [],
    ),
  )
  |> p.path
  |> should_equal(path)

  let path = [1, 0]
  p.do_focus_at(source, path, [])
  |> should.be_ok()
  |> should_equal(
    #(p.Exp(e.Integer(1)), [
      p.CaseMatch(e.Variable("result"), "Ok", [], [], Some(e.Variable("x"))),
    ]),
  )
  |> p.path
  |> should_equal(path)
}
