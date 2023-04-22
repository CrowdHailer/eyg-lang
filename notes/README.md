# Notes

## Type Inference


### Judgements

### Algorithms

Simple Lambda calculus is easily type checked. 
Most of the below algorithms handle extension of at least let polymorphism


#### Algorithm W 
Explained in Hindley Milner Paper

Uses composition of substitutions

#### Algorithm J
Explained in Hindley Milner Paper

Uses a single global substitution. The global substitution doesn't have to 

### Algorithm M
Adds expected type as argument to algorithm.
This get's results in different orders

#### Separate constraint collection from solving

Does Wand fit into this?

## Language extensions

### Recursive functions
#### Fix point
Easy to add is just a function with the required type.
This type is not constructable within the lambda calculus

#### Let Rec

Every Let could test to see if let rec is used.

## Incremental type checking

J with early return is an option

Unison hashes only terms without Free variables
There is the other paper that does both but building up the whole tree is tricky because the env at any given point depends on the tree so can't be cached through modifications

### Differential Datalog

