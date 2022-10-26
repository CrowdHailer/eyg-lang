

Something something tree + zipper
continuations for putting the tree back after transformations
Walking a tree for type stuff that might be incomplete.

Instantiate at call time not fetch from env time
I think we need numbered tvars for when we instantate and when we have parameter ones

Half way experiment where I move type schemas around functions ONLY and instantiate only at call time. and try and set up the env understanding
This gives me everything I need for working out variables used.

```
"binary"

t[] = Binary
```

```
[]

t[] = []
```

```
[a, b]

t[] = Tuple(t[0], t[1])
Record{a: t[0]} < E[]
Record{b: t[1]} < E[]
```

```
{a: []}


t[] = Record{a: t[1, 2]}
t[1, 2] = Tuple()
```

```
[] => {}

t[0] = Tuple()
t[1] = Record{}
t[] = Function(t[0], t[1])
```

```
a => a

t[] = Function(t[0], t[1])
E[a] = Record{E[], a: t[0]}
Record{a: t[1]} < E[a]

[a => a, a => a]

t[] = Tuple(t[0], t[1])
t[0] = Function(t[0,0], t[0,1])
// probably best to link list all the way up with E[0] = E[]
E[0,a] = Record{E[], a: t[0,0]}
Record{a: t[0,1]} < E[0,a]
```

```
a => b

Record{b: t[1]} < E[a]
E[a] = Record{E[], a: t[0]}
t[] = Function(t[0], t[1]) @ E[]

There is a situation where the Function needs to be generalized at an enviroment
Have an algorithm where we walk through the tree and essentially pause execution until we know all the sub branches are resolved

E[] can be resolved and even if b is not known we know it comes from the outside
t[] = ForAll(t[0] Fn(t[0]) -> t[1])

All the 
```

```

```

```
let a = []
b

Record{b: t[]} < E[a]
t[1] = Tuple([])
t[0] = t[1]
E[a] = Record{E[], a: t[1]}
```

```
a([])

Record{a: t[0]}
t[] = Inst(t[0], with: t[1])
t[1] = Tuple()
```

