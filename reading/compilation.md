Transpilation to tiny go possible
1. transpile to code with lot's of anys
2. know from type of lifted function what types should be generated.

Transpilation gives me concurrency and arduino (tinygo) does the actually compiler exist in WASM.
- min caml slides goes through steps well http://www.kb.ecei.tohoku.ac.jp/~sumii/pub/FDPE05.pdf
- crash course to min caml https://esumii.github.io/min-caml/tutorial-mincaml-1.eng.htm


Crafting interpreters goes via a VM, and implemented in GO. !!!!!!!!!! (could just follow this then immutable beans)

- https://github.com/hurryabit/pukeko A toy compiler based on SPJ's "The Implementation of Functional Programming Languages" LAZY and loads of different machines

## General optimisations
- https://compiler.club/compiling-lambda-calculus/
- https://compileroptimizations.com/
- https://www.stephendiehl.com/llvm/#instructions recomended from fission chat
- All of matt might stuff https://matt.might.net/articles/cesk-machines/
- SECD machine

## Serious backends
- LLVM
- QBE https://c9x.me/compile/ start here if I want to not do LLVM, but probably stay higher
- GRIN https://grin-compiler.github.io/

## other vms

- atom vm (erlangy)
- lunatic (erlangy)

## GC
GC is very part of compilation but only interesting if going the compilation route.
- Nim has choice of memory management, including using go's
- https://github.com/candy-lang/candy is a minimal functional lang
- CakeML Verified https://www.cambridge.org/core/services/aop-cambridge-core/content/view/E43ED3EA740D2DF970067F4E2BB9EF7D/S0956796818000229a.pdf/the-verified-cakeml-compiler-backend.pdf
- Grain is fairly functional and targets WASM

- Percius https://www.microsoft.com/en-us/research/uploads/prod/2020/11/perceus-tr-v1.pdf
- http://dmitrysoshnikov.com/compilers/writing-a-memory-allocator/#video-lecture
- https://degaz.io/blog/632020/post.html Experimenting with Memory Management for Basil

- Counting immutable beans https://leanprover.github.io/talks/IFL2019.pdf


https://matt.might.net/articles/cps-conversion/ How to compile with continuations


https://www.microsoft.com/en-us/research/wp-content/uploads/2016/08/algeff-tr-2016-1.pdf In practice though we wish to simplify the types more
and leave out ‘obvious’ polymorphism. In Koka we adopted
two extra type rules to achieve this


Working out a normalisation

A,A,a,b,c

A,a,b,c + Func
a,b,c + Func,Func
b,c, + Arg(a),Func
c + Arg(x) + Let(x),A,a,b
+  +  Let(x),A,a,b


let x = a b
x c
---

A,a,A,b,c
a,A,b,c + Func
A,b,c + Arg(a)
b,c + Func,Arg(a)
c + Arg(b),Arg(a)

let x = b c
a x


-- list

A,A,Cons,x,T
Cons,x,T + Func,Func
x,T + Arg(Cons),Func
T, Cons1(x)

T Cons1,Cons1()

-- select
A,Select(x),y
Select(x),y + Func



-- let

L(x),