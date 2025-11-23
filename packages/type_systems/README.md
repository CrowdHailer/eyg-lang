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


6. The type assignment algorithm

Requires the unification algorithm of Robinson

MGU is most general unifier, this specifies that all substitutions are required by the set of types.

This paper describes the algorithm. https://www.cs.cornell.edu/courses/cs6110/2017sp/lectures/lec23.pdf

Substitutions
Mathematical notation: S = {x ↦ fg(z), wg ↦ g(y)}
Logic notation: S = {x/fg(z), wg/g(y)} or {fg(z)/x, g(y)/wg}

Clearer understanding of the unification and J algorithm
https://www.cl.cam.ac.uk/teaching/1415/L28/type-inference.pdf

## Chapter 2: Top down error messages

- (Lee & Yi, 1998) "Proofs about a Folklore Let-Polymorphic TypeInference Algorithm"
https://dl.acm.org/doi/pdf/10.1145/291891.291892

While Algorithm W is elegant it is not designed to produce good error messages.
Algorithm M, introduced a top-down approach with better error messages.

Algorithm M. is described as a folklore Algorithm.
This is because it was used based on an intuition that it would work, before it was formally proven.
I believe the name M is an upside down w.

Because algorithm W is proven to give the "principle type" algorithm M must give the same answer for all programs that type check. However, for programs that do not type check, algorithm M can give more informative error messages.

This is a general topic in understanding type checkers, a type checker can show a program can be inconsistent but cannot say what that correct program should be.

## Efficieny Algorithm J and beyond.

The W algorithm is amenable to proving but has lots of substitutions

---
I am trying to write a tutorial that works through the steps of type inference algorithms. I want to level up from the basic through to a fully featured understanding of the EYG type system.

The EYG type system has.
* total inference.
* Is based on hindley milner,
* Has efficient type inference based on level.
* User Row types for extensible records and unions.

This is the previous notes I have made.

# Efficient type inference with levels
This algorithm is related to algorithm J and is best described by [this summary](__https://okmij.org/ftp/ML/generalization.html__)
In this case it is combined with opening and closing of effects as described in [section 3.2](__https://arxiv.org/pdf/1406.2061.pdf__)
Open close is only possible in Let and Var (also Builtin) nodes. This is part of the proof.
A simple demonstration is that open cannot be done in unification because a function arg cannot be opened.
I think there is a generalisation here related to co/contra variance. But I have not rationalised it
Ideally it would be possible to use levels for the closing of effect types, however I think that would require effects being one level deeper than normal type variables. I also how no idea how to demonstrate this as sound.
However, the performance loss for effects is not too bad because when looking for free variables only the type has to be considered and not the whole environment. Not having to enumerate the environment is the main improvement of the levels algorithm.
This algorithm (J) rather than M (and my JM implementation) is unconstrained in the final type.
i.e. types of expressions are found, and then unified with a context. In M the context is typed and unified with each expression as it is reached.
Bottom up allows for easier memoisation. Top down potentially has more focused errors and allows you to specify what type the whole program should have. i.e. (request) -> response for a server.
This algorithm is threads an effect type to save lots of unification with open effect type variables.
Only Apply expressions can create an effect.
Types added to metadata are check to see if they would generalise if assigned to a let. This is done by running gen one level above the current expression. This is done so that later unification of rows does not increate the type. The unification of a type in an environment is different to the intrinsict type of an expression.
Effects are not generalised, only closed, so that the field values of the effect are unified where possible.
This choice is mostly for ergonomics.
Schema's could be saved to the env but the will not unify at all, an unification of fields is helpful
I think it is possible to adapt the M algorithm with context typing, to improve editor integration, with closed effects in the meta data. This is only worth doing if we are sure M gives better type errors

Please write me the tutorial with a chapter for each new concept. Please reference the original papers to original concepts whenever possible