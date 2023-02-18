constant folding < compile time evaluation

need fn(type) -> ast

fn unit(_type) -> {
    Ok(Tuple([]))
}

let format = fstring -> type -> {
    Ok(Tree)
}

format("hello, %s")!("world")

let load = code -> type -> {
    check(code, type)
}

let env = type -> {
    different for each type
    Not generic because returns an object
}

previous version took typed tree and ran expand_provider with it


let main = _ -> {
    let a = foo
    ok(format(foo)<>)()
}

Call(Provider, Exp)

I want there to be a way where impossible not to typeness but is it built on unsafe


eval

let x = add(1, 2)
let y = todo
let z = x

expand OR run in interpreter, I don't think that I can make up values for the generator at runtime,
because don't have afterward information

I don't want interpreter to track line number
One of the problems was if the function was generic what does the provider do. Then it might want to wait#
However in fn is generic and types all in args then we can allocate at runtime BUT means runtime work