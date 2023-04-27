# Unison


Makes use of Abstract Binding Trees. https://semantic-domain.blogspot.com/2015/03/abstract-binding-trees.html


unison-hashing-v2/src/Unison/Hashing/V2
defines all the terms in the tree an uses reference utils to do hashing

```haskell
hashed $ hash b == hashed (hash b)
```

Once in the hash' function. Var is De Brijun index so int64


Steps the compiler goes through
https://github.com/unisonweb/unison/blob/477371ba97a019fe36294a76faed52190ef29d75/parser-typechecker/src/Unison/Runtime/docs.markdown
