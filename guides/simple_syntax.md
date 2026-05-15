# EYG Syntax Guide

EYG is a type-safe scripting language with managed effects.
It has a minimal surface area: everything is an expression, there are no statements, and effects are explicit.

---

## Comments

Lines beginning with `//` are comments. They are ignored by the parser.

```eyg
// This is a comment
let x = 5
// x is now 5
x
```

---

## Literals

### Integers

Integers are written as sequences of digits. Negative integers use a leading `-`.

```eyg
42
-7
0
```

### Strings

Strings are enclosed in double quotes. Supported escape sequences:

| Escape | Meaning |
|--------|---------|
| `\n`   | Newline |
| `\t`   | Tab |
| `\r`   | Carriage return |
| `\"`   | Double quote |
| `\\`   | Backslash |

```eyg
"hello, world"
"line one\nline two"
"she said \"hi\""
```

---

## Variables

A variable is any lowercase identifier (letters, digits, and underscores, starting with a letter or underscore).

```eyg
x
my_value
counter1
```

---

## Let Bindings

`let` binds a value to a name. In a block (at the top level or inside a function body), multiple `let` bindings are written on successive lines and their scope extends to the end of the block.

```eyg
let x = 5
let y = 10
x
```

In expression position (nested), `let` takes two expressions: the value and the continuation.

```eyg
let x = 5 x
```

### Destructuring Records

`let` can destructure a record into its fields. Each field is extracted by name.

```eyg
let {name: first, age: n} = person
first
```

If the variable name matches the field name, the `: variable` part can be omitted:

```eyg
let {name, age} = person
name
```

An empty destructuring pattern `{}` is valid and binds nothing:

```eyg
let {} = record
result
```

---

## Functions (Lambdas)

Functions are written with a parameter list in parentheses, `->`, an opening `{`, a body expression, and a closing `}`.

```eyg
(x) -> { x }
```

Multiple parameters are separated by commas. Multiple-argument functions are curried — each parameter produces a nested single-argument function.

```eyg
(x, y) -> { x }
```

### Destructuring Parameters

Function parameters can be record patterns:

```eyg
({name, age}) -> { name }
```

### Calling Functions

Apply a function by appending a parenthesised argument list:

```eyg
let double = (x) -> { !int_multiply(x, 2) }
double(5)
```

Multiple arguments are written separated by commas. Since functions are curried, `f(a, b)` is syntactic sugar for `f(a)(b)`.

```eyg
let add = (x, y) -> { !int_add(x, y) }
add(3, 4)
```

---

## Function Application (Calling)

Any expression followed by `(args)` applies it as a function. Chained calls are left-associative.

```eyg
f(x)
f(x)(y)
outer(inner(value))
```

---

## Records

Records are ordered collections of named fields, written with `{}`.

```eyg
{}
{name: "Alice", age: 30}
```

### Field Access

Fields are accessed with `.`:

```eyg
person.name
```

### Record Update (Overwrite)

`{..record}` passes a record through unchanged. Prepending field assignments with `..record` overwrites those fields in the existing record:

```eyg
{age: 31, ..person}
```

### Record Shorthand

When the field name and variable have the same name, you can omit the `: value`:

```eyg
let name = "Alice"
{name}
// equivalent to {name: name}
```

---

## Lists

Lists are written with `[]`. Items are separated by commas. A trailing comma is allowed.

```eyg
[]
[1, 2, 3]
["a", "b",]
```

### Spread

`..expr` spreads an existing list as the tail:

```eyg
[1, ..rest]
[0, ..list]
```

---

## Tags (Variants)

Tags create tagged values (like union variants). A tag name starts with an uppercase letter.

```eyg
Ok
Error
True
False
```

Tags are applied as functions:

```eyg
Ok(value)
Error("something went wrong")
```

---

## Match

`match` deconstructs tagged values. Cases are written as `TagName variable -> { expression }`.

```eyg
match result {
  Ok(value) -> { value }
  Error(msg) -> { 0 }
}
```

The match expression can be written inline (with the subject before the `{}`):

```eyg
match Ok(5) {
  Ok(n) -> { n }
  Error(_) -> { 0 }
}
```

Or in "function" form (without a subject), producing a function that takes the value to match:

```eyg
let handle_result = match {
  Ok(value) -> { value }
  Error(_) -> { -1 }
}
handle_result(Ok(42))
```

### Else Branch

An else branch catches any tag not handled by previous cases. It is written with `|`:

```eyg
match x {
  Ok value -> { value }
  | (other) -> { -1 }
}
```

---

## Effects

EYG separates the description of an effect from its implementation. Scripts declare effects they need; the runner decides what to do with them.

### Perform

`perform EffectName` sends an effect. The effect name must start with an uppercase letter.

```eyg
perform Log("hello")
```

### Handle

`handle EffectName` returns a handler function for the named effect:

```eyg
handle Log
```

`handle` is used to install custom effect handlers in advanced embedding scenarios.

---

## Builtins

Builtins call built-in runtime operations. They start with `!` followed by a lowercase identifier.

```eyg
!int_add(3, 4)
!int_multiply(x, y)
!string_append("hello", " world")
```

See [`builtins_reference.md`](./builtins_reference.md) for the full list.

---

## References

A reference is an immutable content-addressed module identifier. It starts with `#` followed by a valid base32-encoded CID.

```eyg
#bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy
```

---

## Packages

A package reference starts with `@`. Three forms are accepted:

| Syntax            | Meaning                                                              |
|-------------------|----------------------------------------------------------------------|
| `@standard`            | Latest published version (resolved at evaluation time).              |
| `@standard:3`          | Exactly version `3`. The hash is whatever the registry has for it.   |
| `@standard:3:bafyrei…` | Exactly version `3`, pinned to a specific module CID.                |

The version is a positive integer. The pinned hash, when given, must be a valid base32-encoded CID.

A bare `@standard` references the latest pulled release of that package.
Pin a version (`@standard:3`) for reproducible scripts.
Provide a hash (`@standard:3#…`) to not require trust in the package hub.

---

## Imports

`import` loads a workspace-relative module by path. The path must be a string literal.

```eyg
let fs = import "../eyg_packages/fs/index.eyg"
let {list} = import "../eyg_packages/standard/index.eyg"
```

The imported value is the module's exported value (usually a record of functions).

---

## Vacant

`vacant` (shown as `?` in the structural editor) is a placeholder for an expression that has not yet been written. It has no textual syntax but appears in the IR. The parser produces `Vacant` when a `let` binding is the last line of a block with no following expression.

---

## Complete Example: Filtering Files

```eyg
let fs = import "../eyg_packages/fs/index.eyg"
let {list} = import "../eyg_packages/standard/index.eyg"

let files = fs.list_files({root: ".", ignore: [".git"]})
let gleam_files = list.filter(
  (path) -> { !string_ends_with(path, ".gleam") },
  files
)
gleam_files
```

## Complete Example: Pattern Matching

```eyg
let parse_age = (s) -> {
  match !int_parse(s) {
    Ok(n) -> { Ok(n) }
    Error(_) -> { Error("not a number") }
  }
}

match parse_age("42") {
  Ok(age) -> { perform Print(age) }
  Error(msg) -> { perform Print(msg) }
}
```