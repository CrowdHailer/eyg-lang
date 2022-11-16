# Type inference

A Hindley–Milner (HM) type system is a classical type system for the lambda calculus with parametric polymorphism.
Several Algorithms are described for infering HM types. Algorithm W, M 

Various extensions exist, when considering extensions do they leave inference complete without annotations.
- https://www.cs.princeton.edu/courses/archive/spring12/cos320/typing.pdf explaining typing
- https://steshaw.org/hm/hindley-milner.pdf A good walkthrough, that helped explain to me the fix point
  ```
   * let map = (fix ( map f s.
    (cond (null s) nil
    (cons (f (hd s)) (map f (tl s)))))) in map *)
  ```
- https://gergo.erdi.hu/projects/tandoori/Tandoori-Compositional-Typeclass.pdf A thorough explination of algorithm W vs M
  M is the version when a target type is specified. TODO read compositional type system
- https://github.com/7sharp9/write-you-an-inference-in-fsharp Writing interence in Fsharp through various features like purity and Rows
  TODO does the mutable version explain effect types
- https://github.com/sdiehl/write-you-a-haskell/blob/master/chapter7/poly/src/Infer.hs Write you a haskell is also good to follow
- https://stanford-cs242.github.io/f19/lectures/03-1-functional-basics.html for recursive inferences
- https://pauillac.inria.fr/~fpottier/publis/emlti-final.pdf quite long
- http://pauillac.inria.fr/~fpottier/slides/fpottier-2014-09-icfp.pdf Walk through of algorithms. 

- https://cs.brown.edu/~sk/Publications/Books/ProgLangs/2007-04-26/plai-2007-04-26.pdf Explaination of typing judgements. Also web applications as continuations

- simple recursion split let rec tackle early from types https://link.springer.com/content/pdf/10.1007/978-3-030-45237-7_12.pdf 


### Type vs Kind

Values have types, types have Kinds
Int, Maybe(Int), Fn(Int) -> Int all have kind * (Concrete types)
Maybe has kind * -> * Type constructor

- https://cs.stackexchange.com/questions/111430/whats-the-difference-between-a-type-and-a-kind In detail

# TODO

- MLsub for recursion
- implement a iso vs equi recursion
- ATSUSHI for rows
- links-lang equirecursive types

### Error messages

Error given is dependent on infer order. 
One thing is to move to constrains that might be reorderable. generalise and instantiate make this hard 

- https://studenttheses.uu.nl/bitstream/handle/20.500.12932/23979/eremondi_thesis_final.pdf?sequence=2&isAllowed=y
- http://www.cs.uu.nl/research/techreps/repo/CS-2006/2006-055.pdf Strategies for solving constraints in program analysis
  - https://www.researchgate.net/publication/27707172_Ordering_Type_Constraints_A_Structured_Approach
    More from the same authors
- http://www.cs.uu.nl/research/techreps/repo/CS-2002/2002-031.pdf generalizing Hindley-Milner Type inference

### Rows


Row types describe Extensible Record and Variant types. They do not define Enums or nominal type
Seems like implicit Free Row types are kept around, how does this effect caching?

Row extension can be solved by ALWAY being modification, Don't know how this works for unions
If we have unions for effects do we get the same need for tracking nope values. though a union won't crash if meaningless values are matched on which works for now. Is tracking unused branches
the same complexity as keeping a list of not in row labels.
- read details of koka paper to decide this?

- https://www.cse.chalmers.se/~abela/foetuswf.pdf A predictive analysis of structural recursion
- http://web.cecs.pdx.edu/~mpj/pubs/96-3.pdf early description of things
- http://www.pllab.riec.tohoku.ac.jp/~ohori/research/toplas95.pdf Has an explanation of the algorithm ATSUSHI OHORI fairly thoroughly defined 
  based on W it could be extended fairly well. useful standard for doing the row types
  - Fixes some issues by only allowing extension -> this is the one I should make next
  - https://smlsharp.github.io/en/ in language
- https://arxiv.org/pdf/2108.06296.pdf Need to understand why kinds are brought into it
- https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/scopedlabels.pdf This paper describes Records that have shadowing i.e. overwriting a field leaves it discoverable when a field is removed.
  Author Daan. Part of IFIP working group 2.16 on programming language design https://languagedesign.org/

#### Advanced

- https://github.com/owo-lang/MLPolyR 
- https://people.cs.uchicago.edu/~blume/papers/icfp06.pdf first class cases
  This also talks quite a lot about recursive types
- http://www.cs.uu.nl/research/techreps/repo/CS-2004/2004-051.pdf first class labels
- https://ps.informatik.uni-tuebingen.de/research/functors/equirecursion-fomega-popl16.pdf Data Generic Programming, maybe structural like im looking for.

### Recursion

hash consing is a technique used to share values that are structurally equal
```
hash("[5,Rec(0)]")
0.[Int, 0.[Int,0]]

overwrite(l = 4, r)

0.[[Some(0) | None]  4]
Some([[0 | None] 4])
```
Which paper always has a rec thing

- http://gallium.inria.fr/~fpottier/publis/gauthier-fpottier-icfp04.pdf canonical forms of recursive types
- https://stanford-cs242.github.io/f18/lectures/03-1-recursion.html stanford notes

Paper on first class cases talks about recursive types
- https://www.cs.cmu.edu/~aldrich/courses/819/slides/rows.pdf 
  Rows with recursion, detailed
- https://github.com/stedolan/mlsub MLSub language
  - Stephen Dolan Maintaining functional backend https://github.com/stedolan/malfunction personal website not resolving
  - https://www.repository.cam.ac.uk/bitstream/handle/1810/261583/Dolan_and_Mycrof-2017-POPL-AM.pdf?sequence=1&isAllowed=y paper
  - https://www.cs.tufts.edu/~nr/cs257/archive/stephen-dolan/thesis.pdf thesis
  - https://github.com/LPTK/simple-sub scala version of simple sub
    Has type canonicalisation
- https://dl.acm.org/doi/pdf/10.1145/3409006 autometa for rec
  Would like to infer lowest recursive signature but does not

### Recursive data types

Recursion is fairly easily handled using a `let rec` construction and a fixpoint for type inference.
However for trivial inference this only works for types that are not recursive or that are nominal.
This doesn't work for structural typing. 

- https://www.cs.cmu.edu/~fp/courses/98-linear/handouts/rectypes.pdf Definition of what are recursive types but not how to infer them
- https://basics.sjtu.edu.cn/~xiaojuan/tapl2016/files/lec8_handout.pdf walks through defining a hungry function. 
  Part of series including inference. TODO can we explain structural inference.

### Effect types
- https://lmcs.episciences.org/1004/pdf Inferring Algebraic effects koka relates


