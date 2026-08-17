# EYG IR

Work with the intermediate representation of the [EYG](https://eyg.run) language.
The EYG language is "AST first", there is no textual syntax.
Instead the [AST specification](https://github.com/CrowdHailer/eyg-lang/blob/main/ir/README.md) is the public interface of the language.

This means the language does not need a lexer parser.
Writing interpreters or compilers is therefor much simpler.

This library defines:
- A Gleam data structure for working with EYG programs.
- Create immutable references for EYG programs using the [dag-json](https://ipld.io/docs/codecs/known/dag-json/) codec.

[![Package Version](https://img.shields.io/hexpm/v/eyg_ir)](https://hex.pm/packages/eyg_ir)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/eyg_ir/)

```sh
gleam add eyg_ir@1
```
```gleam
import eyg/ir/dag_json

pub fn main() {
  let bytes = simplifile.read_bits("my_program.eyg.json")
  let source = dag_json.from_block(bytes)
}
```

Further documentation can be found at <https://hexdocs.pm/eyg_ir>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Tree traversal

Functions that operate on ASTs often duplicate boilerplate that is required to navigate the tree data structure.
Generalised tree traversal functions allow for reuse of the common parts.

Iterating over a list is natural as each item has a single successor
However a tree is a rich data structure each node could have zero, one or many children.
Because of this there are multiple ways to operate over the tree.
A tree may be explored depth first or breadth first.
Depth first search can visit a parent before, during or after visiting its children.
Nodes can be visited bottom up or top down.

Multiple algorithms navigating the tree in the same order will have different shapes, the procedure might:
- transform the tree without accumulating information.
- accumulate information without modifying the tree.
- accumulate information and modify the tree.
- rely on asynchronously available information.
- be fallible and need to break out of the traversal.

#### Example

A simple property of the AST is how large it is.
As an example, without any traversal function this function looks like the following.

```gleam
pub fn size(node) {
  let #(exp, _meta) = node
  case exp {
    Let(_label, value, then) -> 1 + size(value) + size(then)
    Lambda(_label, body) -> 1 + size(body)
    Apply(func, arg) -> 1 + size(func) + size(arg)
    _ -> 1
  }
}
```

This function bakes in the knowledge that `Let`, `Lambda` and `Apply` are the only nodes with children.
The `_` captures all remaining expression varients and assumes they are leaves, have size 1.
If the AST was modified to include other nodes with children we would need to remember to update the size function or the catch all clause would give the wrong answer.

Using a traversal helper the size function simplifies to.

```gleam
fn size(node){
  use acc, _node <- fold(node, 0)
  continuation.return(acc + 1)
}
```

This version has no explicit knowledge of the AST structure does not require modification if and when the AST changes.

Can yse collect builtins as another example

#### Continuations

All of the traversal functions are built on continuations.
This allows the same helpers to be use with results, promises or any other shape of transformation.
Continuations will be assumed knowledge for the result of this post.
Check out [this blog post](https://crowdhailer.me/2026-07-15/abstracting-effects-with-continuations/) for an introduction.

### The basics

Traversal over a tree requires a canonical shape of the tree.
Which child is "before" the other needs to be specified.

Several **one-layer** functions define operating over a tree in canoncal order.

In EYG only two nodes have more than one child
Here we can see the canonical order in the children function.

```gleam
fn children(node: Node(a)) -> List(Node(a)) {
  let #(exp, _meta) = node
  case exp {
    tree.Lambda(label: _, body:) -> [body]
    tree.Apply(func:, argument:) -> [func, argument]
    tree.Let(label: _, definition:, body:) -> [definition, body]
    _ -> []
  }
}
```

The `childen` function can accumulate any value but does not rebuild a tree.
To rebuild a tree the foundational function is `map_children`.
The identity law applies to map children.

```gleam
map_children(node, identity) == node
```

### Fold: turn a tree to a summary

A fold is our first recursive function that will visit the whole tree.
The default fold is a pre-order fold.
This fold threads an accumulator through the parent then each of it's children.

The formal name for a fold over recursive data is **catamorphism**.

```gleam
pub fn fold(node: Node(a), acc: b, f: fn(b, Node(a)) -> K(t, b)) -> K(t, b) {
  do_fold([node], acc, f)
}

fn do_fold(
  nodes: List(Node(a)),
  acc: b,
  f: fn(b, Node(a)) -> K(t, b),
) -> K(t, b) {
  case nodes {
    [] -> continuation.return(acc)
    [n, ..rest] -> {
      let rest = list.append(children(n), rest)
      use acc <- continuation.then(f(acc, n))
      do_fold(rest, acc, f)
    }
  }
}
```

This is enough to build the size example above.
We can also rewrite the gather example.
Stop example on finding empty variable

### Rewrite: transform a tree

A rewrite transforms a tree into another tree.
The type of attached metadata can change in the transformation.

The default rewrite function works bottom up.
This means the transformation function sees children that have already been rewritten and the type signature for the transformation function accepts a Node with different types for the metadata and nested metadata.

```gleam
pub fn rewrite(
  node: Node(a),
  rule: fn(#(tree.Expression(b), a)) -> K(t, Node(b)),
) -> K(t, Node(b)) {
  let recur = fn(child) { rewrite(child, rule) }
  let #(exp, meta) = node
  use rebuilt <- continuation.then(map_children(exp, recur))
  rule(#(rebuilt, meta))
}
```

This is the default approach as it does not fail to terminate.
It the parent node was visited first and the transformation function replaced a single node with more than one then both would have to be visited which could result in the same transformation.

There is a rewrite until stable versio

A rewrite could rename builtins

```gleam
fn normalize_builtin(node: Node(a)) -> Node(b) {
  let #(exp,meta)
  case node.0 {
    Builtin("add") ->
      #(Builtin("int_add"),meta)
    other ->
      other
  }
  |> continuation.return
}

```

A rewrite can remove immediatly called lambdas

```gleam
fn remove_immediate_function(node: Node(a)) {
  let #(exp, _meta) = node
  case exp {
    tree.Apply(#(tree.Lambda(param, #(tree.Variable(var), _)), _), value)
      if param == var
    -> continuation.return(value)
    _ -> continuation.return(node)
  }
}
```

TODO Explain why general beta-reduction of `Apply(Lambda(parameter, body), argument)` requires capture-avoiding substitution rather than this simple identity rule.