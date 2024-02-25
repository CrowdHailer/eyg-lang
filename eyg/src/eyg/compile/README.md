# Compilation

Compilation path follows two main resources.

- [MinCaml](https://www.kb.ecei.tohoku.ac.jp/~sumii/pub/FDPE05.pdf)
- [Generalized Evidence Passing for Effect Handler](https://www.microsoft.com/en-us/research/uploads/prod/2021/08/genev-icfp21.pdf)
  - Long version (https://www.microsoft.com/en-us/research/uploads/prod/2021/03/multip-tr-v4.pdf)


```
(f) -> {
  let x = 1
  let z = f("")
  let y = 1
  perform Log(z)
  
}
```

```js
const evv = []
const yielding = false

((_$0) => {
  let x$1 = 1;
  let z$3 = f("")

  // join point j10
  let j10 = (z$3) => {  
    let y$7 = 1;
    return perform("Log", z$3);
  }
  return yielding ? push(j10) : j$10(z$3)
})
```

```js
let evv = []
let yielding;

((_$0) => {
  let x$1 = 1;
  return may_lift(f(""), (z$3) => {  
    let y$7 = 1;
    return lift("Log", z$3);
  }) 
})

perform("Log", x, () => {
  
})

// Is there a way to check for tail resumption if handler is passed as var and not AST?
// Monad or pure by returning an `{$E "label"} object
// TODO merge bubbled list when effect raised in resumption
// Not tail resumptive
function handle(label, handler, exec) {
  evv = [{marker: label, handler}]
  let value = exec({})
  while (yielding && yielding.marker == label) {
    value = yielding.op(resumable(yielding.bubbled))
  }
  return value
}

function lift(label, value) {
  let marker = label
  let op = "from evv"
  let bubbled = []
  yielding = true
}

function may_lift(value, then) {
  if yielding {
    yielding.bubbling = [then, evv];
  } else {
    return then(value)
  }
}
```
TODO test the library
TODO add builtins from module
Is it tail resumptive
Did I build a pure yield version