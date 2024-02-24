# Efficient type inference with levels

This algorithm is related to algorithm J and is best described by [this summary](https://okmij.org/ftp/ML/generalization.html)
In this case it is combined with opening and closing of effects as described in [section 3.2](https://arxiv.org/pdf/1406.2061.pdf)

Open close is only possible in `Let` and `Var` (also `Builtin`) nodes. This is part of the proof.
A simple demonstration is that open cannot be done in unification because a function arg cannot be opened.
I think there is a generalisation here related to co/contra variance. But I have not rationalised it
Ideally it would be possible to use levels for the closing of effect types, however I think that would require effects being one level deeper than normal type variables. I also how no idea how to demonstrate this as sound.
However, the performance loss for effects is not too bad because when looking for free variables only the type has to be considered and not the whole environment. Not having to enumerate the environment is the main improvement of the levels algorithm.

This algorithm (J) rather than M (and my JM implementation) is unconstrained in the final type.
i.e. types of expressions are found, and then unified with a context. In M the context is typed and unified with each expression as it is reached.
Bottom up allows for easier memoisation. Top down potentially has more focused errors and allows you to specify what type the whole program should have. i.e. (request) -> response for a server.

This algorithm is threads an effect type to save lots of unification with open effect type variables.
Only `Apply` expressions can create an effect.

Types added to metadata are check to see if they would generalise if assigned to a let. This is done by running gen one level above the current expression. This is done so that later unification of rows does not increate the type. The unification of a type in an environment is different to the intrinsict type of an expression.

Effects are not generalised, only closed, so that the field values of the effect are unified where possible.
This choice is mostly for ergonomics.
Schema's could be saved to the env but the will not unify at all, an unification of fields is helpful

I think it is possible to adapt the M algorithm with context typing, to improve editor integration, with closed effects in the meta data. This is only worth doing if we are sure M gives better type errors
