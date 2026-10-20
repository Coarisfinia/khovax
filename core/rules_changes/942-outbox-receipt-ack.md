---
issue: 942
---
Every command carries the newest request id up to which the profile saw its outbox's requests acknowledged, and the world keeps that mark instead of the receipts it covers, refusing any of them sent again; the outbox draws its ids in order ([#942](https://github.com/Coarisfinia/khovax/issues/942)).
