# Onboarding — from clone to first merged PR

**Target: half a day from clone to a green local build.** If any step takes materially longer, that
is a defect in *our documentation*, not in you — open an issue labelled `type:docs` and we fix it.

---

## Day 1 — get it running

### 1. Tools

| Tool | Why | Check |
|---|---|---|
| `git`, `python3` (≥3.10) | everything | `python3 --version` |
| **Verilator** ≥ 5.0 | simulation, lint | `verilator --version` |
| `riscv64-unknown-elf-gcc` | building software | `riscv64-unknown-elf-gcc --version` |
| `spike` | co-simulation reference | `spike --help` |
| `sail` / `riscof` | compliance (layer 3) | `riscof --version` |
| `pandoc` + Chrome | building the docs | `make check-tools` |

```bash
git clone https://github.com/meds-uet/meds-s1
cd meds-s1
make check-tools        # tells you what is missing
make test-unit          # should print PASS
make check              # structure conventions
```

If `make test-unit` prints `=== PASS`, your environment is good.

### 2. Read, in this order

1. [`README.md`](../../README.md) — what this is
2. [`specs/SCOPE_CONTRACT.md`](../../specs/SCOPE_CONTRACT.md) §2–3 — what v1.0 does and does **not** do
3. The specification PDF, Part I — the platform and why it exists
4. [`CODING_STANDARD.md`](CODING_STANDARD.md) — §2, §3, §8 at minimum
5. Your own project's page in the Project Catalogue

Then read **one module end to end**: [`rtl/core/s1_alu.sv`](../../rtl/core/s1_alu.sv) and
[`verif/unit/tb_s1_alu.sv`](../../verif/unit/tb_s1_alu.sv). They are the house style. Everything you
write should look like them.

### 3. Find your project

[`PROJECTS.md`](../../PROJECTS.md) maps every catalogue project (M-01 … R-07) to the directories it
touches. Your project page states its objective, deliverables and definition of done.

---

## Day 2 — first change

```bash
git checkout -b m-01/uart-wrapper        # <project-id>/<short-description>
# ... work ...
make check && make lint && make test-unit
git commit -m "m-01: add AXI4-Lite UART wrapper

Wraps the OpenTitan UART with the register window of SPEC section 24.

Closes #42"
git push -u origin m-01/uart-wrapper
```

Open a PR against `main`, fill in the template, and link your issue. CI runs in under twenty
minutes. **Nothing merges red**, including work by the architect.

---

## Week 1 — the bridge exercise (recommended)

If you came through `rv-workshop`, do the bridge exercise (project **M-16**): take your own
single-cycle RV32I core, wrap it in the platform's memory interface, and run the platform's RV32I
architectural tests against it.

Most workshop cores fail, informatively. That is the point — it is the fastest way to understand why
the verification harness exists, and it turns one day of workshop into a working mental model of the
whole platform.

---

## The contribution ladder

| Tier | To enter | You do | Reviewed by |
|---|---|---|---|
| **T0** Contributor | `rv-workshop` done | a peripheral via config, a HAL driver, a directed testbench, a benchmark, docs | 1 reviewer |
| **T1** Implementer | 2 merged T0 PRs | one module against a frozen spec | module owner |
| **T2** Owner | 1 T1 module delivered *and verified* | own a module and its spec; review T1 work | tech lead |
| **T3** Architect | — | own an **interface**; only these people may change `specs/INTERFACES.md` | architect + faculty |

Everyone starts at T0, including people who think they shouldn't. The first two tasks are about
learning the harness, not about the difficulty of the code.

---

## Where to ask

| Question | Where |
|---|---|
| "How do I…", "Why is…" | GitHub **Discussions → Q&A** — searchable, unlike chat |
| A design proposal | **Discussions → Design**, before it becomes an issue |
| Something is broken | an issue with `type:bug` |
| Blocked for more than a day | say so in the weekly sync thread — **same day**, not next week |

A blocked contributor who waits a week has lost a sixth of a semester. Raising a blocker early is
the expected behaviour, not an admission of anything.

---

## Getting stuck is normal

The first PR is the hardest because you are learning the harness, the review culture and the domain
at once. Budget two weeks for it. By the third it will take an afternoon.
