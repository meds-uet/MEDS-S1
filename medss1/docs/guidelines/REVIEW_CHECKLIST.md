# Review Checklist

**Reviews are the main teaching mechanism in this lab.** Review accordingly: explain the *why*, cite
the rule or spec section, and distinguish blocking from optional.

---

## For the author, before requesting review

- ☐ `make check && make lint && make test-unit` all green locally
- ☐ Branch is rebased on current `main`
- ☐ PR template filled in, issue linked
- ☐ Module `README`/`docs/modules/` page added or updated (R-D3)
- ☐ No change to a frozen interface — or an `interface-change` issue is linked
- ☐ Benchmark impact stated if you touched the core or memory path
- ☐ You have read your own diff once, as if you were the reviewer

## For the reviewer

### Blocking — these cost someone else a week

- ☐ **Inferred latch** — every `case` pre-assigns its outputs (R-C3)
- ☐ **Memory not behind `meds_s1_sram`** (R-C5)
- ☐ **Frozen interface changed** without an approved `interface-change` issue
- ☐ **No testbench**, or a testbench that prints without comparing
- ☐ **Hard-coded widths** that break another configuration (R-C7)
- ☐ **`valid` depends combinationally on `ready`** (R-C10)
- ☐ **Missing module documentation** (R-D3) — the next contributor pays, not the author
- ☐ **Reset policy violated** — local reset generation, or sync assert (R-C4)
- ☐ **CDC written by hand** outside a named synchroniser (R-C9)

### Worth raising, not blocking

- ☐ Naming that will confuse the next reader
- ☐ A comment saying *what* instead of *why* (R-D5)
- ☐ Duplication that should move to `rtl/common/` or `verif/common/`
- ☐ A file heading toward the 800-line limit (R-C6)
- ☐ Test coverage that misses backpressure, reset, or full/empty

### How to write the comment

```
BLOCKING — R-C3: `result_o` is not assigned when `op_i` is ALU_PASS_B, which
infers a latch. Pre-assign a default before the case; see s1_alu.sv:113.

nit: `cnt` reads better as `beat_count` here.

suggestion: this loop is the same shape as the one in s1_lsu.sv — worth
pulling into verif/common/ once there is a third user, not yet.
```

Prefix optional comments with `nit:` or `suggestion:`. **Approve with comments** when nothing is
blocking — holding a PR over style is how you lose contributors.

### Never do this

**Do not rewrite a contributor's branch yourself to "just fix it".** They learn nothing and they
stop contributing. Comment, and let them push the fix.

---

## Service level

**48 hours.** If you cannot review in that time, reassign — silence is not a review. A part-time
contributor blocked on review for a week has lost a sixth of their semester.

## Approvals required

| Change touches | Approvals | Who |
|---|---|---|
| docs, tests, apps | 1 | anyone T1+ |
| a module's internals | 1 | module owner |
| `rtl/core/`, `gen/` | 2 | module owner + tech lead |
| a frozen interface | 2 | architect + every affected implementer |
| `.github/`, `platform.lock` | 1 | tech lead |
