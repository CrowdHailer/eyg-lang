The EYG hub has 2 methods of making code public.

1. Share by content identifier
2. Pubish a release.

Currently anyone can publish and anyone can share.

The following tasks need completing.

- [ ] Sharing must be rate limited by ip
- [ ] Mist/Wisp need modifying to expose ip to the application.
- [ ] Publishing must be limited to a specific unteathered signatory.
- [ ] There must be a gleam `dev` task that can write a new row in the database to allow a signatory to publish releases under a given name
- [ ] Implement a `CreateKey` effect that takes a variant `[Eddsa(opts) | ..others]` and returns a structured variant `Eddsa(keydata)`
- [ ] Implement a `Sign` effect that takes key data an a binary and returns the binary signature. 
- [ ] Expose an `EYGParse` effect that takes a string and returns the AST
- [ ] Add share and publish functions to the eyg hub module
- [ ] Write a `eyg/cli.eyg` module that allows a user to use the EYG shell to share and publish.
- [ ] Document using the eyg cli module
- [ ] Write complete tests for the EYG hub
- [ ] Write complete tests for the EYG cli module, mock all effects using handlers
- [ ] Review all the difficulties and next steps and add tasks to this list for them
- [ ] implement the solutions to difficulties and next steps.
- [ ] Write a guide for sharing a module
- [ ] Write a guide for publishing a module
- [ ] Write a manifesto on the principle purpose of untethererd

Write any new sub tasks to this list.
Mark items as done in this list when they are complete, code is tested and formatted.

NOTE:

- Document any notes and difficulties as you encounter them
- Document and next steps that would make this process clearer to users.
- The is no web way to get a package name. I must be contacted to gain access which I will do manually using the script.
- The new crypto effects must work with a standard specification of a key. Use names and arguments that would match the webcrypto API
- The eyg module is not published yet. so write documentation using the import syntax
- The new crypto effects must be described by touch_grass
- Switch all gleam module resolution to local paths to test the integrations
- Vendor into `./packages` any gleam packages that need modifying.

i.e.
```
let eyg = import "path/to/eyg"
let code = fs.read("path/to/my/module.eyg")
match eyg.share(code) {
  Ok(_) -> { todo }
  Error(_) -> { todo }
}
```