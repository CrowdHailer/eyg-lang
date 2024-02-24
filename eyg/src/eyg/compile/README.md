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
const evv = []
const yielding = false

((_$0) => {
  let x$1 = 1;
  jump(f(""), (z$3) => {  
    let y$7 = 1;
    return perform("Log", z$3);
  }) 
})

perform("Log", x, () => {
  
})
```
TODO test the library
TODO add builtins from module