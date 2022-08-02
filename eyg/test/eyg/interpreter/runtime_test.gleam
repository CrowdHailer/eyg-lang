import gleam/io
import gleam/map
import eyg/interpreter/runtime as r
import eyg/ast/expression as e
import eyg/ast/pattern as p

fn step(bytecode) { 
    case bytecode {
        #(value, env, []) -> #(value, env, Error(Nil)) 
        #(value, env, [next, ..rest]) -> {
            let #(value2, env2) = next(value, env)
            #(value, env, Ok(#(value2, env2, rest)))
        }
    }
 }

fn run(bytecode) { 
    let #(value,_env, next) = step(bytecode)
    case next {
        Error(Nil) -> value 
        Ok(bytecode) -> run(bytecode)
    }
 }

pub fn binary_rtest() {
    let empty = map.new()
    let source = e.binary("hello")

    let stack = r.compile(source, empty)

    assert r.Binary("hello") = run(stack)
}

pub fn variables_rtest() {
    let empty = map.new()
    let source = e.let_(p.Variable("a"), e.binary("foo"), e.variable("a"))

    let stack = r.compile(source, empty)
    assert r.Binary("foo") = run(stack)
}

// TODO community implement a debugger
pub fn tagged_rtest() {
    let empty = map.new()
    let source = e.tagged("A", e.tagged("B", e.binary("hello")))

    let stack = r.compile(source, empty)
    assert r.Tagged("A", r.Tagged("B", r.Binary("hello"))) = run(stack)
}