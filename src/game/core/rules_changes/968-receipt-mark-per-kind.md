---
issue: 968
---
A command carrying a request carries the mark of that request's kind, the newest id up to which the profile saw every request of that kind acknowledged, and a command without a request carries none, so a request stuck in the outbox holds back only its own kind's mark and the other features still forget their receipts ([#968](https://github.com/Coarisfinia/khovax/issues/968)).
