## What

<!-- One or two sentences. -->

## Why

Closes #

## Spec reference

<!-- Which section of SPEC / INTERFACES.md this implements or changes. -->

## Checklist

- [ ] `make check` clean (structure + docs gates)
- [ ] `make lint` clean — no new waivers, or waivers justified in `verif/verilator.vlt`
- [ ] `make test-unit` green; new/updated testbench included
- [ ] `docs/modules/<module>.md` added or updated (R-D3, NFR-7)
- [ ] All four configs still elaborate
- [ ] Generated files regenerated if `configs/*.yaml` changed
- [ ] **No change to a frozen interface** — or an `interface-change` issue is linked below
- [ ] Branch is < 2 weeks old and rebased on `main`

## Testbench evidence

<!-- Paste the PASS line, e.g.  === PASS : 4206 checks === -->

```
```

## Benchmark impact

<!-- Required if you touched rtl/core/, rtl/cache/ or rtl/fabric/.
     NFR-10: a regression over 3% blocks merge without written justification. -->

CoreMark/MHz before → after: n/a

## Anything a reviewer should look at closely

<!-- Be honest here. "I am not sure the reset behaviour is right" saves everyone time. -->
