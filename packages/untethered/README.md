# Untethered

Location independent datastructures to represent mutable entities.

The core datastructre is a vine, a vine is a merkle tree with support for efficient checking of membership and signing.
A signatory is an intrinsic vine.
A package/publisher is a delegated vine.

A Ledger stores a single history for an entity.
A consumer can be an auditor, or not.
A Ledger should always be an auditor
A Wallet stores keys, entity history and alias, another name is device/fob/keyring key with sticky label

Usecases
Unteathered lobsters.
