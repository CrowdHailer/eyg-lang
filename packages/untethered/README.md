# Untethered

Location independent datastructures to immutably record decisions.

Evidence of a decision is recorded by signing a next entry in a chain.
Two entries can be efficiently checked for there membership in the same chain using sequence numbers and entity.

## Substrate

The Untethered substrate is the location independent data strucutre

## Ledger

A Ledger stores a single history for an entity.
A consumer can be an auditor, or not.
A Ledger should always be an auditor
A Wallet stores keys, entity history and alias, another name is device/fob/keyring key with sticky label


## Usecase

EYG's trust chain foundation is the untethered data structure.
The EYG hub is the ledger for recording the accepted history.
In this role the hub is trusted, but it is only trusted to record.
It is not possible for the hub to sign releases or modify signatories without the owner key.

A signatory is an intrinsic vine.
A package/publisher is a delegated vine.


## Notes

Naming is hard. Previously I used the term vine for a data structure with a counter
