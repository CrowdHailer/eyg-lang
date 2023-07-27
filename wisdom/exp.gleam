pub fn do_build() -> Nil {
    

    case  {
         -> 
    }
}



1
let x = {
    2 3
    let y = a
    4
    b
}
5
c


L(x) L(y), "a", "b", "c"    [Top]
L(y), "a", "b", "c"      - [LValue(0),LThen(0)]
"a", "b", "c"      - [LValue(y), LThen(y), LThen(x)]
"b", "c"      - [LThen(y), LThen(x)]

L(x)  "a",L(y), "b", "c" 
"a", L(y), "b", "c"      - [LValue(x)]
L(y), "b", "c"      - [LThen(x)]
"b", "c"      - [LValue(y)]

fix(build, source, stack, count) {
    let head, ..source = pop(source)
    put values
    update stack
}



L(x), "a", "b" - []
"a" "b"        - [LValue(x)]
"b"            - [LThen(x)]