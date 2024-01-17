# CEK interpreted runtime

Exposes small step semantics by using the `step` function.
This returns the `Next` type which either breaks or continues the loop.
Break is a better word that halt or stop because execution can be resumed.

Separating the small steps from the runner allows alternative execution modes.
i.e. single step debugger, or live coding examples.

*Is there a card version of the small step execution,
maybe but I haven't worked out copying a function to a closure*

Extrinsic effects and builtin functions have different semantics.
The effect interface is to limited to call a passed in function using small steps.
Small steps are not needed if the function will be called in the different context such as new thread, or in response to web requests or mouse clicks.
BUT that does not mean there will never be a need for a small step call in the same thread.
Maybe a full powered API is possible, one that exposes env and stack to handlers, but that also has a builder for the simple case.
Full access to env and k is possible by intercepting the `UnhandledEffect` error.
This is how the prompt effect for the shell and `await` function are implemented.

Calling builtin functions only fails on incorrect value types once all args are present.
This makes implementing the builtin simpler, but error messages are potentially less specified.
Poorly targeted error messages are particularly problematic when passing around partially applied functions

In an old implementation using `use` for continuations, having a separate loop and step function was required to make constructing the stack tail optimised.
However it was still possible to blow the stack calling the continuation.

Env and Stack depend on each other.
It would be nice to separate them to their own files but this introduces circular dependencies.
Separating them would allow both to have an `empty` constant

Both eval and apply may affect the env and stack.
Builtins that accept functions need to return next steps for for the small step loop,
this is achieved by adding to the stack.
There needs to always be an env in the #(C, E, K) return state.
In some cases env is not used. i.e. calling a function, or popping a delimited stack frame.
Closures carries a captured env and builtins are evaluated externally to the env.
Removing the env from some stack types or the `apply` seems possible but might not simplify things.
It is possible to recursively apply until you reach a value with an env state.
However this introduces recursion in places other than the loop function which will not be tail optimised.
This will also mean some values might not be captured from an automated runner that tracks values
Removing env by calling apply on demand might be called with an empty stack and need to complete.
This means we can't assume the only place a loop stops is in the loop function.
This will make the use of the `Next` type more pervasive in step functions.

The path (reversed) is also passed in the state for debugging,
however it adds noise to the interpreter.
Maybe the path can be combined with an expression variant because only expressions have a location.

The `Resume` value makes the `Value` type dependent on the interpreter state.
To prevent circular dependencies the `Value` type is parameterised by a Context (the part of the interpreter state needed for resumption).
It should be possible to change a resumption into source code, a function to call the continuation with passed in value.
This would remove the circular dependency but would require expensive translation for all resumptions,
it would however allow capturing and serialising of resumptions, which currently panics
