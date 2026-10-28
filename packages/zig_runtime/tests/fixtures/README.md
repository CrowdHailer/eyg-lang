Evaluation fixtures are copied unchanged from the native runtime's Gleam oracle,
commit be502aa03df926a8f9df474a0a7fe16c8fb14fbd.

Keep native compatibility checks reproducible against that version. The root
specification also covers newer language features, including Datalog queries,
which this pinned native runtime does not implement. The Gleam runtimes continue
to run the current root specification.
