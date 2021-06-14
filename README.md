# Spotless

Ultimate developer experience

## Architecture

Should not be tied to a single application type. could be:

- CLI
- Server
- Client
- Static blog
- Compiler
- SPA/App

What things do these have in common? i.e. error handling, state.
What are the axis we can organise along. Batch, UI etc

It would be nice to consider tackling systems of these applications. i.e. client & server a.la blitz.js

[User interface architectures](https://staltz.com/unidirectional-user-interface-architectures.html)
[comparing reactivity models](https://dev.to/lloyds-digital/comparing-reactivity-models-react-vs-vue-vs-svelte-vs-mobx-vs-solid-29m8)

### Niceties

- Time travelling debugger
- No runtime errors
- Bug tracking, for assert
- logging, perimeter
- deployment
- rational, visible views

### FRP

- [Can FRP be a monad](https://stackoverflow.com/questions/28293831/can-functional-reactive-programming-frp-be-expressed-using-monads)
  - https://www.youtube.com/watch?v=Agu6jipKfYw
- FRP is hard https://news.ycombinator.com/item?id=21430745

### spreadsheets

- Haskell typed spreadsheet
- https://github.com/Gabriel439/Haskell-Typed-Spreadsheet-Library

### Cycle js

- implemenatation of very pure reactive
  - https://project-awesome.org/cyclejs-community/awesome-cyclejs
  - too reactive http://cyclow.js.org/

### Svelte

Svelte is sort of FRP but with a bunch of general things made specific.

```html
<script>
  let count = 0;

  function handleClick() {
    count += 1;
  }
</script>

<button on:click="{handleClick}">clicks: {count}</button>
```

`count` is essentially an observable.
Does a selection of observables that the executor that updates them result in a single state item?
I think it might the whole component is essentially a context state and count is a field in the context.

```js
count += 1;
context = { ...context, count: context.count + 1 };
```

- [svelte + rx](https://timdeschryver.dev/blog/unlocking-reactivity-with-svelte-and-rxjs)
- apparently svelte needs a virtual dom https://dev.to/svaani/svelte-needs-a-virtual-dom-1ebm

### Elm

- The Elm Architecture (TEA)
  - Note that Elm abandoned FRP
    - https://elm-lang.org/news/farewell-to-frp
  - shares many concepts with how React manages state. see [Convergent evolution](https://www.youtube.com/watch?v=jl1tGiUiTtI)
    - common item was unidirectional data flow.
  - What would TEA look like in Gleam. Elm has `Elm.HTML` would it simply be a case of making that?
- Elm discourages components.
  - This is because it introduces internal state.
  - https://package.elm-lang.org/packages/edkv/elm-components/latest/
- Elm has its own package manager and this forces versioning, at the cost of a smaller ecosystem. i.e. chooses a subset over a superset of packages.
- Build, Discover, Refactor.
  - Just build it. [Scaling Elm apps](https://www.youtube.com/watch?v=DoA4Txr4GUs)
    - I should also use this logic for seeing what falls out of how to build Gleam apps.
      Problem if making a spotless product, need enough examples.
      That's probably the best reason to open source from day one.
    - Video also mentions that organisation follows from guarantees.
    - Really good advice on managing without components - Narrowing Types is the main advice
    - 31 min in, helper function on state if always taking a model returning a model can be passed through a pipe chain
    - 40 min in, reusing a whole sign up form
- Is there an introducing TEA talk.
- Make the embedded engineer jealous
- How does tasks vs side effect commands work?
- [Elm markup](https://www.youtube.com/watch?v=8Zd3ocr9Di8)
  - 14 min Has the idea of a markdown/document AST and also has options of editing the output and to stringing itself

Microservices with separate databases are the same breaking a system apart as components with state.
A central SQL DB is the same choices as a central Elm style state, but probably much smaller as one user.

if state broken into components do we always assume message passing? async?

### Eve

Had a nice way to ship out state of program for debugging

### React

- om.js clojure version

### Reflex

- https://reflex-frp.org/
- FRP Haskell Lib
- Reflex Dom -> GHCjs dom builder
- Reflex Platform -> app backends
- https://www.youtube.com/watch?v=me8H-jdAxE4
  - FRP is hard
  - I think reflex is too hard http://docs.reflex-frp.org/en/latest/reflex_docs.html

##### Other

- https://mithril.js.org/
- https://ractive.js.org/

```rust
fn text() {

}

fn div(children) {
    let element = document.createElement('div')
    case children {
        Text(inner_update) -> #(
            element,
            fn (x) -> {
                element.setTextContent = inner_update(x)
                // do the same with attributes
            }

        )
    }
}

let #(element, update) = text(fn(x) -> to_string(x))
let #(elements, update) = div(fn(x) -> attributes, [
    // hmm how do you do nested on the functions
    text()
    div()
    if
])

// collect all the updates together
render(x, previous, element) {
    previous == x return
    reflect.(element, settextcontent)
}

let #(x, #(y, element)) =
html(
    bind(x, fn(x) -> {
        bind(y, fn(y) -> {
            string(x + y)
        })
    })
)
```

Just build, discover, refactor
