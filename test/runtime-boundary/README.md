# Runtime boundary guard

This fast source-level check prevents portable floating-point formatting from
moving back into the private C application runtime. It runs before compiler
construction in the normal ladder.

The executable floating-point acceptance test remains authoritative for behavior.
This guard only enforces implementation ownership: formatting lives in
`stdlib/io.weave`, while the host boundary is limited to byte output and string
length.
