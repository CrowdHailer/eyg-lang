---
name: Advanced effects
description: Working with effects and handlers to implement state and other patterns.
---

## Stateful handlers

### Getting started

A common requirement when handling an effect is to depend on some state outside the computation raising the effects.
For example an `Increment` effect needs to track the current count.
Or in testing a handler for `StandardOut` might build up a state consisting of all messages written.

Below is the implementation of a single stateful `Increment` effect.

```eyg
let with_counter = (initial, computation) -> {
  handle Increment(
    (_unit, resume) -> {
      (state) -> {
        resume(state)(!int_add(state, 1))
      }
    },
    (_) -> { 
      let value = computation({})
      let finish = (count) -> { {count, value} }
      finish
    }
  )(initial)
}

with_counter(0, (_) -> { 
  let _ = perform Increment({})
  let _ = perform Increment({})
  let _ = perform Increment({})
  "Done"
})
```

Each handle expression applies to a single effect label.
Handlers can be nested to handle multiple effects but care needs to be taken to manage the same state between multiple handlers.

This is part of the design to keep the type system simple, though the restriction might be relaxed in the future.
If you want more than one effectful operation you have two options.

### A generic stateful effect

```eyg
let with_counter = (initial, computation) -> {
  handle Update(
    (transform, resume) -> {
      (state) -> {
        let state = transform(state)
        resume(state)(state)
      }
    },
    (_) -> { 
      let value = computation({})
      let finish = (count) -> { {count, value} }
      finish
    }
  )(initial)
}

let increase = (amount) -> {
  let _ = perform Update((state) -> { !int_add(state, amount) })
  {}
}

let get = (_) -> {
  perform Update((state) -> { state })
}
with_counter(0, (_) -> { 
  let _ = increase(3)
  let value = get({})
  let _ = perform StandardOut(!int_to_string(value))
  let _ = increase(2)
  !int_to_string(value)
})
```

This counter value can be increased and retrieved.
The functions `get` and `increase` are the public interface to the stateful operation.
A generic `Update` effect takes a transformation from the current state to the new state.

## Shared stateful handlers

The generic approach is only possible if you control the design of the effects which is not always possible.
For example we might want to test a library with the `Get` and `Increase` effects.

In that case effects can be bounced to a new effect which you do control.

```eyg
let with_state = (initial, f) -> {
  // Generic State effect owns the shared state.
  let run = handle State((update, resume, state) -> {
    let state = update(state)
    resume(state)(state)
  }, (_) -> {
    // These handlers translate operations; they do not hold separate state.
    let value = handle Increase((amount, resume) -> {
      let _ = perform State((state) -> { !int_add(state, amount) })
      resume({})
    }, (_) -> {
      handle Get((_, resume) -> {
        let state = perform State((state) -> { state })
        resume(state)
      }, f)
    })

    let finish = (state) -> { {state, value} }
    finish
  })
  run(initial)
}

with_state(0, (_) -> {
  let before = perform Get({})
  let _ = perform Increase(2)
  let middle = perform Get({})
  let _ = perform Increase(-1)
  let after = perform Get({})
  [before, middle, after]
})
// {state: 1, value: [0, 2, 1]}
```


## Returning functions

Type checking the following will fail with the error `this expression has a recursive type`.

```eyg
let main = (_) -> {
  let f = perform Get({})
  f("")
}
main({})
```

Why this fails is not immediately obvious.
The type of `f` appears in the reply type of the `Get` effect row of the `main` function.
When `f` is called its effects are unified with the effects in the current function block, i.e. the `main` block.
This results in a recursive type trying to be constructed.

It is recommended not to return functions from effects because of this.