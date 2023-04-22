## Adding binary-size(a) to js backend.
This would be a very sensible addition as it stays in whole byte size subsections.
However it requires rewriting of sizing part of the code.
Currently the total offset is calculated at compile time and this would need to be a runtime thing

Files needed for updates
```
 compiler-core/src/javascript/pattern.rs           | 38 +++++++++++++++++++++++--
 compiler-core/src/javascript/tests/bit_strings.rs | 11 +++++++
 compiler-core/templates/prelude.js                |  4 +++
 test/language/test/language_test.gleam            | 10 +++++++
 ```
