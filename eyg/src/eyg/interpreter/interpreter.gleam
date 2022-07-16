import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/list
import gleam/map
import gleam/string
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/codegen/javascript

pub type Object {
    Binary(String)
    Tuple(List(Object))
    Record(List(#(String, Object)))
    Tagged(String, Object)
    Function(p.Pattern, e.Expression(Dynamic, Dynamic), map.Map(String, Object))
    BuiltinFn(fn(Object) -> Object)
}

fn value_map(pairs, func) { 
    list.map(pairs, fn(pair) { 

    let #(k, v) = pair
        #(k, func(v))
     })
 }

pub fn extend_env(env, pattern, object) { 
    case pattern {
        p.Variable(var) ->  map.insert(env, var, object)
        p.Tuple(keys) -> {
            assert Tuple(elements) = object
            assert Ok(pairs) = list.strict_zip(keys, elements)
            list.fold(pairs, env, fn(env, pair) { 
                let #(var, value)= pair
                map.insert(env, var, value)
            })
            }
        p.Record(fields) -> todo("not supporting record fields here yet")
    }
 }

pub fn exec(source, env)  {
    let #(_, source) = source
    case source {
        e.Binary(value) -> Binary(value)
        e.Tuple(elements) -> Tuple(list.map(elements, exec(_, env)))
        e.Record(fields) -> Record(value_map(fields, exec(_, env)))
        e.Access(record, key) -> {
            assert Record(fields) = exec(record, env)
            assert Ok(value) = list.key_find(fields, key)
            value
        }
        e.Tagged(tag, value) -> Tagged(tag, exec(value, env))
        e.Case(value, branches) -> {
            assert Tagged(tag, value) = exec(value, env)
            assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                let #(t, _, _) = branch
                t == tag
            })
            let env = extend_env(env, pattern, value)
            exec(then, env)

        }
        e.Let(pattern, value, then) -> {
            exec(then, extend_env(env, pattern, exec(value, env)))
        }
        e.Variable(var) -> {
            io.debug(var)
            assert Ok(value) = map.get(env, var)
            value
        }
        e.Function(pattern, body) -> {
            Function(pattern, body, env)
        }
        e.Call(func, arg) -> {
            let arg = exec(arg, env)
            case exec(func, env) {
                 Function(pattern, body, captured) -> {

                    let inner = extend_env(captured, pattern, arg)
                    exec(body, inner)
                }
                BuiltinFn(func) -> {
                    func(arg)
                }
                _ -> todo("Should never be called")
            }

        }
        e.Hole() -> todo("interpreted a program with a hole")
        e.Provider(_, _, generated) -> {
            io.debug(source)
            Tuple([])
            exec(dynamic.unsafe_coerce(generated), env)
            // todo("providers should have been expanded before evaluation")
            }
    }
}

pub fn render_var(assignment) { 
    let #(var, object) = assignment
    case var {
        "" -> [] 
        _ -> case object {
            Binary(content) -> [string.concat(["let ", var, " = ", "\"", javascript.escape_string(content), "\";"])]
            Tuple(_) -> todo("tuple")
            Record(fields) -> {
                let term = list.map(
                    fields,
                    fn(field) {
                    let #(name, Binary(content)) = field
                    string.concat([name, ": ", "\"", javascript.escape_string(content), "\""])
                    },
                )
                |> string.join(", ")
                [string.concat(["let ", var, " = ","{", term, "}",";"])]
            }
            Tagged(_, _) -> todo("tagged")
            // Builtins should never be included, I need to check variables used in a previous step
            Function(_,_,_) -> todo("this needs compile again but I need a way to do this without another type check")
            BuiltinFn(_) -> []
        }
    }
 }
