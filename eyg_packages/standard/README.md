# standard

The `@standard` package: integer, string, list, result, boolean,
http, url, mime, task, keylist, binary, logs.

The package ships as IR JSON (`index.eyg.json`); source is elsewhere
and not editable in this repo. Use it via the package reference:

```eyg
let list = @standard.list
```

## What's exported

Run `eyg eval -c '@standard'` for the live record listing. The major
sub-modules are:

| Sub-module | Functions                                                                                                |
|------------|----------------------------------------------------------------------------------------------------------|
| `integer`  | `add`, `subtract`, `multiply`, `divide`, `absolute`, `compare`, `parse`, `to_string`                     |
| `string`   | `append`, `concat`, `join`, `length`, `lowercase`, `uppercase`, `starts_with`, `ends_with`, `replace`, `split`, `split_once`, `to_binary`, `from_binary` |
| `list`     | `map`, `flat_map`, `filter`, `filter_map`, `find`, `try_map`, `pop_map`, `fold`, `pop`, `flatten`, `intersperse`, `reverse`, `append`, `head`, `move`, `contains`, `length` |
| `result`   | `unwrap`, `expect`                                                                                       |
| `boolean`  | `and`, `or`                                                                                              |
| `binary`   | `from_integers`                                                                                          |
| `http`     | `get`, `post`, `send`, `response`, `ok`, `not_found`, `html`, `body`, `bearer`, `header`, `path`, `port`, `query` |
| `url`      | `parse_query`                                                                                            |
| `mime`     | `css`, `html`, `js`, `json`, `plain`                                                                     |
| `keylist`  | `find`, `map_value`, `pop`                                                                               |
| `task`     | `async`                                                                                                  |
| `logs`     | `capture`, `log`                                                                                         |

## Known quirks

`list` is not consistent about argument order — some helpers take
the list first, others take a predicate or function first. See the
`.agents/cheatsheet.md` entries E7 and E8 for the table. When in
doubt, query the live record:

```
eyg eval -c '@standard.list.filter'
//                                  ^ shows the next-arg name
```
