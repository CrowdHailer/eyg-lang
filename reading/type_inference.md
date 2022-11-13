# Type inference

A Hindley–Milner (HM) type system is a classical type system for the lambda calculus with parametric polymorphism.
Several Algorithms are described for infering HM types. Algorithm W, M 

Various extensions exist, when considering extensions do they leave inference complete without annotations.

- https://steshaw.org/hm/hindley-milner.pdf A good walkthrough, that helped explain to me the fix point
  ```
   * let map = (fix ( map f s.
    (cond (null s) nil
    (cons (f (hd s)) (map f (tl s)))))) in map *)
  ```
- https://gergo.erdi.hu/projects/tandoori/Tandoori-Compositional-Typeclass.pdf A thorough explination of algorithm W vs M
  M is the version when a target type is specified.
- https://github.com/7sharp9/write-you-an-inference-in-fsharp Writing interence in Fsharp through various features like purity and Rows
  TODO does the mutable version explain effect types
- https://github.com/sdiehl/write-you-a-haskell/blob/master/chapter7/poly/src/Infer.hs Write you a haskell is also good to follow
- https://stanford-cs242.github.io/f19/lectures/03-1-functional-basics.html for recursive inferences
- https://pauillac.inria.fr/~fpottier/publis/emlti-final.pdf quite long

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
- https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/scopedlabels.pdf This paper describes Records that have shadowing i.e. overwriting a field leaves it discoverable when a field is removed.  
- https://ps.informatik.uni-tuebingen.de/research/functors/equirecursion-fomega-popl16.pdf Data Generic Programming, maybe structural like im looking for.

### Recursion
### Recursive data types

Recursion is fairly easily handled using a `let rec` construction and a fixpoint for type inference.
However for trivial inference this only works for types that are not recursive or that are nominal.
This doesn't work for structural typing. 

- https://www.cs.cmu.edu/~fp/courses/98-linear/handouts/rectypes.pdf Definition of what are recursive types but not how to infer them
- https://basics.sjtu.edu.cn/~xiaojuan/tapl2016/files/lec8_handout.pdf walks through defining a hungry function. 
  Part of series including inference. TODO can we explain structural inference.

### Effect types
- https://lmcs.episciences.org/1004/pdf Inferring Algebraic effects koka relates