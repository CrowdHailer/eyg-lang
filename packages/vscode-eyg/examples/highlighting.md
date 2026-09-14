# EYG in Markdown

```eyg
let double = (number) -> { !int_multiply(number, 2) }
perform StandardOut("Hello, EYG!\n")
```

This paragraph is Markdown again.

~~~eyg
match Ok(42) {
  Ok(value) -> { value }
  | (_) -> { -1 }
}
~~~
