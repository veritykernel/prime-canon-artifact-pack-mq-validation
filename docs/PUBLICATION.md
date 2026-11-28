# Rendered publication

Use `scripts/publish_rendered_subject.sh <subject-slug>` for the configured
stage destination. The trusted stage root is `/Users/Shared/nuum-work/stage`;
the repository configuration may select only that root's subject file. The
target directory must already exist. The guard accepts
only this verified publisher or its no-effect dry run.

The publisher checks the current view, render execution receipt, and drift
receipt against the expected subject and output path. The execution receipt
must bind the current view hash. That hash covers the complete view spec, the
exact bytes of every active canon node, and the exact bytes of the render
profile, order, targets, and redaction policies. Historical executions without
that binding remain blocked until a separately reviewed successor render. It
reads the rendered source once, verifies the SHA-256 recorded by the execution receipt, and
publishes those same bytes with an atomic replacement inside an open target
directory. It opens every rendered and stage directory component without
following symlinks, rejects linked output leaves, and leaves the existing
target untouched if verification fails. A green drift receipt alone cannot
authorize later changed bytes.

Before publication, every stage directory component must be owned by root or
the invoking user and must not be group or world writable. Root-owned sticky
intermediate directories are allowed; the final stage directory is not. A
group-writable `/Users/Shared/nuum-work/stage` is rejected. Its owner must
qualify a protected destination or an
approved permission change, including the other consumers, before a fresh
signed render and publication. The publisher does not change that directory.

`scripts/check_render_drift.py` and its shell wrapper are read-only. A failed
comparison stays failed on every subsequent check. Repair requires a reviewed
render with a new execution receipt and its frozen view hash; the checker never
advances that baseline or commits a receipt.
