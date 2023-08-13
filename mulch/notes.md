continuations

E is a continuation (Evaluation context)

```
E[exit(v)] -> exit(v)
E1[catch{E2[throw(v)], f}] -> E1[f(v)]
```

```
E[call_cc(f)] -> E[f(x) -> E[x]]
E1[prompt{E2[control(f)]}] -> E1[f(fn(x) -> E2[x])]
```



```
E1[shallow{E2[perform(v)], h}] -> E1[h(v, fn(x) -> E2[x])]
E1[deep{E2[perform(v)], h}] -> E1[h(v, fn(x) -> deep{E2[x], h})]
                               E1[(With func)[(With v)[h]]]
```
```
E[a(b)] -> E[(Arg b)[a]] -> E[(Arg b)(x)] -> E[(Apply x)[b]] -> E[(apply x)(y)]
```


Freeze could exist as a function to make the continuation serializable
This is just a case of serailizing resume
