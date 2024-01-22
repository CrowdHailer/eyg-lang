things are functions

need native things to pass to library of fn's unless we interpreter everywhere
glancing through the module is fine but slow, also means reinventing ffi.

Interpreter everywhere works ok?
running interpreter requires handling out of order types, potentially mutually recursive functions and more

Need interpreter everywhere to be able to handle effects

I'm pretty sure I need evaling if we are going to use compiled modules. 
I need evalling to use ffi

import encoded alows using external. If we get to external we still need to import and then use that.

A future with an interpreter is what makes the whole thing cool with effects etc. There is no real gleam script future without it. I can definetly do effects

Rendering to Gleam -> JS is what I want to end up doing because that's the universal demo. But
Native rendering of functions from rust code.

I'll be faster in Gleam than Rust, passing through to native is something I can try to Do
Doing it in native terms means you still need to handle statements to take case of the env and passing to subsequent statements.
Can't keep rebuilding a session module because that will rebuild previous statements

How does calling with named fields work

