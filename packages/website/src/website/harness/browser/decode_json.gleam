import eyg/analysis/type_/isomorphic as t

pub const l = "DecodeJSON"

pub const lift = t.Binary

pub fn reply() {
  t.result(
    t.List(
      t.record([
        #(
          "term",
          t.union([
            #("True", t.unit),
            #("False", t.unit),
            #("Null", t.unit),
            #("Integer", t.Integer),
            #("String", t.String),
            #("Array", t.unit),
            #("Object", t.unit),
            #("Field", t.String),
          ]),
        ),
        #("depth", t.Integer),
      ]),
    ),
    t.String,
  )
}

pub fn type_() {
  #(l, #(lift, reply()))
}
