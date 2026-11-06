# unixfs

Encode files and directories as [UnixFS](https://specs.ipfs.tech/unixfs/) blocks, addressed by CIDv1 with sha2-256.

- A file is one block with the `raw` codec.
- A directory is a `dag-pb` node with UnixFS `Directory` data and links sorted by name.

These are the blocks IPFS tools make with `--cid-version=1` and raw leaves,
so the CIDs can be checked against `ipfs add`.
Files that UnixFS would split into several blocks are not supported.

Works on both the Erlang and JavaScript targets.

```gleam
import unixfs.{Link}

let hello = <<"hello\n">>
let file = Link("hello.txt", unixfs.file_cid(hello), 6)
let block = unixfs.encode_directory([file])
unixfs.cid(unixfs.dag_pb_code, block)
// bafybeigdcg7pksx2zk5336vrfsktjodlr4rbfz37qr3koc5xboxe5ekv24
```
