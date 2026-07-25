# Unresolved call validation design

This branch reserves the implementation direction for rejecting function calls whose targets are absent from the complete WIR declaration set before LLVM IR emission.

The validator belongs in the final `weavec` backend. It must scan all `extern` and `fn` declarations before emission, allow recursion and forward references, preserve the existing implicit runtime declarations, and emit `unknown identifier: <name>` so the diagnostics facade can map the call target to canonical source.

This file is temporary design evidence and will be removed when the implementation commit is published.
