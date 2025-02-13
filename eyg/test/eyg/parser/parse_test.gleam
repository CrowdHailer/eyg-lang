import eyg/ir/tree as ir
import eyg/parse
import gleeunit/should

pub fn literal_test() {
  "x"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.Variable("x"), #(0, 1)))

  "12"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.Integer(12), #(0, 2)))

  "\"hello\""
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.String("hello"), #(0, 7)))

  "\"\\\"\""
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.String("\""), #(0, 3)))
  // "<<>>"
  // |> parse.all_from_string()
  // |> should.be_ok()
  // |> should.equal(#(ir.String("hello"), #(0, 7)))
}

pub fn negative_integer_test() {
  "-100"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.Integer(-100), #(0, 4)))
}

pub fn lambda_test() {
  "(x) -> { 5 }"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.Lambda("x", #(ir.Integer(5), #(9, 10))), #(0, 12)))

  "(x, y) -> { 5 }"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Lambda("x", #(ir.Lambda("y", #(ir.Integer(5), #(12, 13))), #(0, 15))),
      #(0, 15),
    ),
  )
}

pub fn fn_pattern_test() {
  // Need both brackets if allowing multiple args
  "({x: a, y: b}) -> { 5 }"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Lambda(
        "$",
        #(
          ir.Let(
            "a",
            #(
              ir.Apply(#(ir.Select("x"), #(2, 3)), #(ir.Variable("$"), #(3, 4))),
              #(2, 4),
            ),
            #(
              ir.Let(
                "b",
                #(
                  ir.Apply(
                    #(ir.Select("y"), #(8, 9)),
                    #(ir.Variable("$"), #(9, 10)),
                  ),
                  #(8, 10),
                ),
                #(ir.Integer(5), #(20, 21)),
              ),
              #(8, 21),
            ),
          ),
          #(2, 21),
        ),
      ),
      #(0, 23),
    ),
  )
}

pub fn apply_test() {
  "a(1)"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(ir.Apply(#(ir.Variable("a"), #(0, 1)), #(ir.Integer(1), #(2, 3))), #(0, 4)),
  )
  "a(10)(20)"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Apply(#(ir.Variable("a"), #(0, 1)), #(ir.Integer(10), #(2, 4))), #(
          0,
          5,
        )),
        #(ir.Integer(20), #(6, 8)),
      ),
      #(0, 9),
    ),
  )

  "x(y(3))"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Variable("x"), #(0, 1)),
        #(ir.Apply(#(ir.Variable("y"), #(2, 3)), #(ir.Integer(3), #(4, 5))), #(
          2,
          6,
        )),
      ),
      #(0, 7),
    ),
  )
}

pub fn multiple_apply_test() {
  "a(x, y)"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(
          ir.Apply(#(ir.Variable("a"), #(0, 1)), #(ir.Variable("x"), #(2, 3))),
          #(0, 4),
        ),
        #(ir.Variable("y"), #(5, 6)),
      ),
      #(0, 7),
    ),
  )
}

pub fn let_test() -> Nil {
  "let x = 5
   x"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(ir.Let("x", #(ir.Integer(5), #(8, 9)), #(ir.Variable("x"), #(13, 14))), #(
      0,
      14,
    )),
  )

  "let x = 5
   x.foo"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Let(
        "x",
        #(ir.Integer(5), #(8, 9)),
        #(
          ir.Apply(
            #(ir.Select("foo"), #(14, 18)),
            #(ir.Variable("x"), #(13, 14)),
          ),
          #(13, 18),
        ),
      ),
      #(0, 18),
    ),
  )

  "let x =
    let y = 3
    y
   x"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Let(
        "x",
        #(
          ir.Let(
            "y",
            #(ir.Integer(3), #(20, 21)),
            #(ir.Variable("y"), #(26, 27)),
          ),
          #(12, 27),
        ),
        #(ir.Variable("x"), #(31, 32)),
      ),
      #(0, 32),
    ),
  )

  "let x = 5
   let y = 1
   x"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Let(
        "x",
        #(ir.Integer(5), #(8, 9)),
        #(
          ir.Let(
            "y",
            #(ir.Integer(1), #(21, 22)),
            #(ir.Variable("x"), #(26, 27)),
          ),
          #(13, 27),
        ),
      ),
      #(0, 27),
    ),
  )
}

pub fn let_record_test() -> Nil {
  "let {x: a, y: _} = rec
   a"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Let(
        "$",
        #(ir.Variable("rec"), #(19, 22)),
        #(
          ir.Let(
            "a",
            #(
              ir.Apply(#(ir.Select("x"), #(5, 6)), #(ir.Variable("$"), #(6, 7))),
              #(5, 7),
            ),
            #(
              ir.Let(
                "_",
                #(
                  ir.Apply(
                    #(ir.Select("y"), #(11, 12)),
                    #(ir.Variable("$"), #(12, 13)),
                  ),
                  #(11, 13),
                ),
                #(ir.Variable("a"), #(26, 27)),
              ),
              #(11, 27),
            ),
          ),
          #(5, 27),
        ),
      ),
      #(0, 27),
    ),
  )

  "let {x, y} = rec
   a"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Let(
        "$",
        #(ir.Variable("rec"), #(13, 16)),
        #(
          ir.Let(
            "x",
            #(
              ir.Apply(#(ir.Select("x"), #(5, 6)), #(ir.Variable("$"), #(5, 6))),
              #(5, 6),
            ),
            #(
              ir.Let(
                "y",
                #(
                  ir.Apply(
                    #(ir.Select("y"), #(8, 9)),
                    #(ir.Variable("$"), #(8, 9)),
                  ),
                  #(8, 9),
                ),
                #(ir.Variable("a"), #(20, 21)),
              ),
              #(8, 21),
            ),
          ),
          #(5, 21),
        ),
      ),
      #(0, 21),
    ),
  )

  "let {} = rec
   a"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Let(
        "$",
        #(ir.Variable("rec"), #(9, 12)),
        #(ir.Variable("a"), #(16, 17)),
      ),
      #(0, 17),
    ),
  )
}

pub fn list_test() {
  "[]"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.Tail, #(0, 2)))

  "[1, 2]"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Apply(#(ir.Cons, #(0, 1)), #(ir.Integer(1), #(1, 2))), #(0, 2)),
        #(
          ir.Apply(
            #(ir.Apply(#(ir.Cons, #(2, 3)), #(ir.Integer(2), #(4, 5))), #(2, 5)),
            #(ir.Tail, #(5, 6)),
          ),
          #(2, 6),
        ),
      ),
      #(0, 6),
    ),
  )

  "[[11]]"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(
          ir.Apply(
            #(ir.Cons, #(0, 1)),
            #(
              ir.Apply(
                #(ir.Apply(#(ir.Cons, #(1, 2)), #(ir.Integer(11), #(2, 4))), #(
                  1,
                  4,
                )),
                #(ir.Tail, #(4, 5)),
              ),
              #(1, 5),
            ),
          ),
          #(0, 5),
        ),
        #(ir.Tail, #(5, 6)),
      ),
      #(0, 6),
    ),
  )

  "[a(7), 8]"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(
          ir.Apply(
            #(ir.Cons, #(0, 1)),
            #(
              ir.Apply(#(ir.Variable("a"), #(1, 2)), #(ir.Integer(7), #(3, 4))),
              #(1, 5),
            ),
          ),
          #(0, 5),
        ),
        #(
          ir.Apply(
            #(ir.Apply(#(ir.Cons, #(5, 6)), #(ir.Integer(8), #(7, 8))), #(5, 8)),
            #(ir.Tail, #(8, 9)),
          ),
          #(5, 9),
        ),
      ),
      #(0, 9),
    ),
  )
}

pub fn list_spread_test() {
  "[1, ..x]"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Apply(#(ir.Cons, #(0, 1)), #(ir.Integer(1), #(1, 2))), #(0, 2)),
        #(ir.Variable("x"), #(6, 7)),
      ),
      #(0, 7),
    ),
  )
  "[1, ..x(5)]"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Apply(#(ir.Cons, #(0, 1)), #(ir.Integer(1), #(1, 2))), #(0, 2)),
        #(ir.Apply(#(ir.Variable("x"), #(6, 7)), #(ir.Integer(5), #(8, 9))), #(
          6,
          10,
        )),
      ),
      #(0, 10),
    ),
  )
}

pub fn record_test() {
  "{}"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.Empty, #(0, 2)))

  "{a: 5, b: {}}"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Apply(#(ir.Extend("a"), #(0, 3)), #(ir.Integer(5), #(4, 5))), #(
          0,
          5,
        )),
        #(
          ir.Apply(
            #(ir.Apply(#(ir.Extend("b"), #(5, 9)), #(ir.Empty, #(10, 12))), #(
              5,
              12,
            )),
            #(ir.Empty, #(12, 13)),
          ),
          #(5, 13),
        ),
      ),
      #(0, 13),
    ),
  )

  "{foo: x(2)}"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(
          ir.Apply(
            #(ir.Extend("foo"), #(0, 5)),
            #(
              ir.Apply(#(ir.Variable("x"), #(6, 7)), #(ir.Integer(2), #(8, 9))),
              #(6, 10),
            ),
          ),
          #(0, 10),
        ),
        #(ir.Empty, #(10, 11)),
      ),
      #(0, 11),
    ),
  )
}

pub fn record_sugar_test() {
  "{a, b}"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Apply(#(ir.Extend("a"), #(0, 2)), #(ir.Variable("a"), #(1, 2))), #(
          0,
          2,
        )),
        #(
          ir.Apply(
            #(
              ir.Apply(#(ir.Extend("b"), #(2, 5)), #(ir.Variable("b"), #(4, 5))),
              #(2, 5),
            ),
            #(ir.Empty, #(5, 6)),
          ),
          #(2, 6),
        ),
      ),
      #(0, 6),
    ),
  )
}

pub fn overwrite_test() -> Nil {
  "{a: 5, ..x}"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Apply(#(ir.Overwrite("a"), #(0, 3)), #(ir.Integer(5), #(4, 5))), #(
          0,
          5,
        )),
        #(ir.Variable("x"), #(9, 10)),
      ),
      #(0, 10),
    ),
  )
  "{..x}"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.Variable("x"), #(3, 4)))
}

pub fn overwrite_sugar_test() -> Nil {
  "{a, ..x}"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(
          ir.Apply(#(ir.Overwrite("a"), #(0, 2)), #(ir.Variable("a"), #(1, 2))),
          #(0, 2),
        ),
        #(ir.Variable("x"), #(6, 7)),
      ),
      #(0, 7),
    ),
  )
}

pub fn field_access_test() {
  "a.foo"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(ir.Apply(#(ir.Select("foo"), #(1, 5)), #(ir.Variable("a"), #(0, 1))), #(
      0,
      5,
    )),
  )

  "b(x).foo"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(ir.Select("foo"), #(4, 8)),
        #(
          ir.Apply(#(ir.Variable("b"), #(0, 1)), #(ir.Variable("x"), #(2, 3))),
          #(0, 4),
        ),
      ),
      #(0, 8),
    ),
  )

  "a.foo(2)"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(
          ir.Apply(#(ir.Select("foo"), #(1, 5)), #(ir.Variable("a"), #(0, 1))),
          #(0, 5),
        ),
        #(ir.Integer(2), #(6, 7)),
      ),
      #(0, 8),
    ),
  )
}

pub fn tagged_test() {
  "Ok(2)"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(ir.Apply(#(ir.Tag("Ok"), #(0, 2)), #(ir.Integer(2), #(3, 4))), #(0, 5)),
  )
}

pub fn match_test() {
  "match { }"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.NoCases, #(0, 9)))

  "match x { }"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(ir.Apply(#(ir.NoCases, #(8, 11)), #(ir.Variable("x"), #(6, 7))), #(0, 11)),
  )
  "match {
      Ok x
      Error(y) -> { y }
    }"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(
          ir.Apply(#(ir.Case("Ok"), #(14, 16)), #(ir.Variable("x"), #(17, 18))),
          #(14, 18),
        ),
        #(
          ir.Apply(
            #(
              ir.Apply(
                #(ir.Case("Error"), #(25, 30)),
                #(ir.Lambda("y", #(ir.Variable("y"), #(39, 40))), #(30, 42)),
              ),
              #(25, 42),
            ),
            #(ir.NoCases, #(47, 48)),
          ),
          #(25, 48),
        ),
      ),
      #(0, 48),
    ),
  )
}

pub fn open_match_test() {
  "match Ok(2) {
    Ok(a) -> { a }
    | (x) -> { 0 }
  }"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(
        #(
          ir.Apply(
            #(
              ir.Apply(
                #(ir.Case("Ok"), #(18, 20)),
                #(ir.Lambda("a", #(ir.Variable("a"), #(29, 30))), #(20, 32)),
              ),
              #(18, 32),
            ),
            #(ir.Lambda("x", #(ir.Integer(0), #(48, 49))), #(39, 51)),
          ),
          #(12, 51),
        ),
        #(ir.Apply(#(ir.Tag("Ok"), #(6, 8)), #(ir.Integer(2), #(9, 10))), #(
          6,
          11,
        )),
      ),
      #(0, 51),
    ),
  )
}

pub fn perform_test() {
  "perform Log"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(#(ir.Perform("Log"), #(0, 11)))

  "perform Log(\"stop\")"
  |> parse.all_from_string()
  |> should.be_ok()
  |> should.equal(
    #(
      ir.Apply(#(ir.Perform("Log"), #(0, 11)), #(ir.String("stop"), #(12, 18))),
      #(0, 19),
    ),
  )
}
