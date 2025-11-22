# A Tutorial on Type Inference: From Basics to the EYG Type System
## Introduction
This tutorial builds understanding progressively, starting from fundamental type inference and advancing to the sophisticated EYG type system. EYG combines several advanced features:

- **Total type inference** based on the Hindley-Milner system
- **Efficient inference using levels** rather than full environment traversal
- **Row types** for extensible records and unions
- **Effect tracking** with an open/close mechanism

Each chapter introduces one concept, building on previous knowledge.

## Chapter 1: The Foundation - Hindley-Milner Type Inference
### The Basic Problem

Type inference solves the question: "Given an expression without type annotations, what is its type?"

### The Hindley-Milner System
The Hindley-Milner (HM) type system, introduced by Hindley (1969) and refined by Milner (1978), provides complete type inference for a lambda calculus with let-polymorphism.

#### Key papers:

- Hindley, R. (1969). "The Principal Type-Scheme of an Object in Combinatory Logic"
- Milner, R. (1978). "A Theory of Type Polymorphism in Programming"
- Damas and Milner (1982) "Principal type-schemes for functional programs"

### Damas and Milner

This paper introduces the algorithmic approach to type inference,
It provides complete type inference for a lambda calculus with let-polymorphism.
This algorithm is what we will implement.

1. Introduction

> The type discipline was studied in [Mil] ,
> where it was shown to be semantically sound, in a
> sense made precise below, but where one important
> question was left open: does the type-checking
> algorithm - or more precisely, the type assignment
> algorithm (since types are assigned by the compiler,
> and need not be mentioned by the programmer) - find
> the most general type possible for every expression
> and declaration? Her

2. The language

The syntax of expressions `e` in the language are given by:

`e ::= x | e e′ | λx.e | let x = e in e′`.


In gleam we can use `todo` to stand in for any unspecified expression.

```gleam
// refer to a variable x.
x

// call a function with a single argument
todo(todo)

// create a function with a single argument
fn(x) { todo }

// create a new variable from one expression in use it in a subsequent one.
let x = todo
todo
```

This defines all the relationships between expressions in this language.
It's worth noting only the last is not part of the lambda calculus.

the syntax of types `τ` and of type-schemes `σ` is given by

`τ ::= α | ι | τ → τ`

`σ ::= τ | ∀ασ`

Our algorithm needs to return a type for every expression, and a type scheme for every let declaration. 

```gleam
pub type MonoType {
  Var(Int)
  Fun(MonoType, MonoType)
  Primitive(Primitive)
}

pub type Primitive {
  Integer
}

pub type PolyType {
  ForAll(Set(Int), MonoType)
}
```

3. Type Instantiation

This makes most sense to me when I am using them.

