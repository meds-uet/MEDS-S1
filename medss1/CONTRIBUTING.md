# Contributing to MEDS-S1

Welcome. This file is the short version; the long versions are linked from each section.

---

## 1. Five minutes to your first build

```bash
git clone https://github.com/meds-uet/meds-s1 && cd meds-s1
make check-tools     # tells you what is missing
make ci              # structure + lint + unit tests -- should be green
```

If `make ci` is green, your environment works. If it is not and the message does not tell you how to
fix it, **that is our bug** — open an issue labelled `type:docs`.

Then read [`docs/guidelines/ONBOARDING.md`](docs/guidelines/ONBOARDING.md).

## 2. Find your work

- Assigned a catalogue project? → [`PROJECTS.md`](PROJECTS.md) maps it to the directories you touch.
- Just arrived? → the `good-first-issue` label.

## 3. The house style

Read these two files end to end before writing anything:

- [`rtl/core/s1_alu.sv`](rtl/core/s1_alu.sv) — the reference module
- [`verif/unit/tb_s1_alu.sv`](verif/unit/tb_s1_alu.sv) — the reference testbench

Your code should look like them. Then skim
[`docs/guidelines/CODING_STANDARD.md`](docs/guidelines/CODING_STANDARD.md) §2, §3 and §8.

The three rules that matter most:

- **R-C3** pre-assign outputs before a `case` — prevents inferred latches
- **R-C5** every memory goes through `meds_s1_sram` — keeps an ASIC port possible
- **R-V2** derive test expectations from parameters, never constants

## 4. Making a change

```bash
git checkout -b m-01/uart-wrapper       # <project-id>/<short-description>
# ... work ...
make check && make lint && make test-unit
git commit -m "m-01: add AXI4-Lite UART wrapper

Wraps the OpenTitan UART with the register window of SPEC section 24.
FIFO depth is 16 to match the second-stage loader's burst size.

Closes #42"
git push -u origin m-01/uart-wrapper
```

Then open a PR, fill in the template, link the issue.

**Rules that are not negotiable:**

- `main` is always green. **Nothing merges red** — that includes the architect.
- Branches live **≤ 2 weeks**. Longer means the task was mis-sized; say so and split it.
- One issue, one squashed commit on `main`.
- Never commit build output (`build/`, `*.vcd`, `obj_dir/`).

## 5. Review

You get a review within **48 hours**, or the reviewer reassigns. Silence is not a review.

Reviews are the main teaching mechanism here, so expect explanation rather than verdicts. Comments
prefixed `nit:` or `suggestion:` are optional; anything else is blocking. See
[`docs/guidelines/REVIEW_CHECKLIST.md`](docs/guidelines/REVIEW_CHECKLIST.md).

If you disagree with a review comment, say so with your reasoning. That is a normal and expected
part of the process, not a confrontation.

## 6. Changing a frozen interface

`specs/INTERFACES.md`, `rtl/socket/`, `verif/conformance/` and `extensions/REGISTRY.md` are
**frozen**. Changing them breaks every attached accelerator, so:

1. Open an issue using the `interface-change` template.
2. State who is affected and what their migration is.
3. Get an architect's approval **before** writing code.

This is not bureaucracy — it is the single mechanism that stops accelerator #7 from breaking
assumptions accelerator #3 relied on.

## 7. Where to ask

| Question | Where |
|---|---|
| "How do I…", "Why is…" | Discussions → **Q&A** (searchable, unlike chat) |
| A design proposal | Discussions → **Design**, before it becomes an issue |
| Something is broken | an issue, `type:bug` |
| Blocked > 1 day | the weekly sync thread — **same day** |

**Any decision made in chat is written into an issue or a doc the same day, or it did not happen.**
Contributors rotate every few semesters; a decision that lives only in a chat scrollback is lost the
moment those people graduate.

## 8. Licence

Apache-2.0. Every file carries the SPDX header — CI checks it. By contributing you agree your work
is licensed the same way.
