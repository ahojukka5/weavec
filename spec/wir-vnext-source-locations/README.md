# WIR vNext source-location fixtures

These fixtures exercise the source-location proposal in
`docs/wir-next-source-locations.md`. They are specification examples, not inputs
accepted by the current WIR v2 backend.

The valid fixtures cover:

- one direct source location;
- multiple source origins for one WIR node;
- a generated WIR node derived from a direct location.

The malformed fixtures cover unknown source and location IDs, reversed byte
ranges, and cyclic generated provenance.

`scripts/check_wir_next_source_locations.py` parses this isolated corpus and
checks the Phase 0 structural rules. It deliberately does not modify or replace
the production WIR parser. The manifest records which fixtures must pass and the
expected diagnostic fragment for each malformed fixture.
