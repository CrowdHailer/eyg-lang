pub type Value {
  B(Bool)
  I(Int)
  S(String)
  L(List(Value))
}

pub type Triple =
  #(Int, String, Value)
