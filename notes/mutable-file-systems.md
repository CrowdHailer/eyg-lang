---
name: Mutable File Systems
description: Design notes for the implementation of mfs.
date: 2026-11-10
---

The cloud file systems is built on a content addressed storage.
Directory and file hashes are specified in the [unixfs](https://specs.ipfs.tech/unixfs/) spec.

MFS is a module in [Kubo](https://github.com/ipfs/kubo/tree/master/fuse/mfs), the go implementation of IPFS.
There was an effort to define a [standard API](https://github.com/ipfs/specs/issues/98) for IPFS implementations.
However it was deemed unnecessary to standardise.

The mfs module uses the Kubo implementation as inspiration but nothing more.

The filesystem created is not a FUSE (Filesystem in USErspace) because it doesn't need to expose standard POSIX API's.
POSIX is the application-facing side of FUSE.