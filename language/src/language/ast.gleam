type Expression(e) {
  // Pattern is name in Let
  Let(name: String, value: e, in: e)
  Var(name: String)
  Binary
  Case
  Tuple
  // arguments are names only
  Function(arguments: List(String), body: e)
  Call(function: e, arguments: List(e))
}

type Node(t) {
    Node(t, Expression(Node(t)))
}

type Option(a){
    Some(a)
    None
}

fn extract_annotation(parsed) {
    case parsed {
        Let(name, value, in) -> Node(None, Let(name, extract_annotation(value), extract_annotation(in)))
        Var(name) -> Node(None, Var(name))
        Binary -> Node(Some("binary"), Binary)
    }
}

// Everything is record constructors
fn main() { 
  let parsed = Let(name: "foo", value: Binary, in: Let(name: "foo", value: Binary, in: Var("foo")))
  extract_annotation(parsed)
}



