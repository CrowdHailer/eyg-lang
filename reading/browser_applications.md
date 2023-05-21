Solid vs Qwik
All the qwik blog https://qwik.builder.io/media/#blogs

Resumable

What's the API?
Week 40@5 min, talking about a main

```
req -> {
    onclick(evt -> {
        render({..state(), count: state.count + 1})
    })
}

let handle_click(target, state) -> new state

let loop(state) -> {
    let Nil = display(render(state))
    let Nil = OnClick(fn(target) -> loop(handle_click(target, state)))
}
```

code capture pretty printing

1. handle fn + switch
   1.5. merge state with override fn
2. demo handle func only evaling code on the button
3. demo rendering on the server
