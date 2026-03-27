Prioritized changes to make

  ┌──────────┬─────────────────────────────┬─────────────────────────────────────────┐
  │ Priority │           Change            │                  Where                  │
  ├──────────┼─────────────────────────────┼─────────────────────────────────────────┤
  │ High     │ Fix git diff to handle      │ commands/ads-qa-review.md               │
  │          │ --single-branch clones      │                                         │
  ├──────────┼─────────────────────────────┼─────────────────────────────────────────┤
  │ High     │ Write diff to file;         │ commands/ads-qa-review.md               │
  │          │ instruct agent to read it   │                                         │
  ├──────────┼─────────────────────────────┼─────────────────────────────────────────┤
  │          │ Embed agent instructions on │                                         │
  │ High     │  dispatch (agent type       │ commands/ads-qa-review.md               │
  │          │ workaround)                 │                                         │
  ├──────────┼─────────────────────────────┼─────────────────────────────────────────┤
  │ High     │ Add !! bang-bang check to   │ rules/ads-qa-review-standards.md        │
  │          │ ADS data patterns checklist │                                         │
  ├──────────┼─────────────────────────────┼─────────────────────────────────────────┤
  │ 
  ├──────────┼─────────────────────────────┼─────────────────────────────────────────┤
  │ Medium   │ Strip HTML before passing   │ commands/ads-qa-review.md               │
  │          │ ticket to agent             │                                         │
  ├──────────┼─────────────────────────────┼─────────────────────────────────────────┤
  │          │ Add explicit RAG query      │                                         │
  │ Medium   │ logging step to agent       │ agents/ads-qa-reviewer.md               │
  │          │ workflow                    │                                         │
  ├──────────┼─────────────────────────────┼─────────────────────────────────────────┤
  