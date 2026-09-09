# Recovery policy

M0/M1 is build-only and cannot modify a phone. The CI and project scripts must
not contain `fastboot flash`, partition-writing `dd`, repartitioning commands,
or AVB-state changes.

Before any later device-side milestone, recovery documentation must be expanded
with the exact stock-image provenance, current slot handling, a tested
non-destructive boot method where supported, and a rollback path. No internal
storage layout change is authorized by the current project scope.
