# ADR-0001 — Platform is MEDS-S1, core is S1-Core


| Name | Meaning |
|---|---|
| **MEDS-S1** | the platform: SoC, generator, BSP, CI, board ports |
| **S1-Core** | the scalar RV64 CPU inside it |
| **MEDS-V** | the RVV vector coprocessor (unchanged) |
| **MEDS-X-\<name\>** | any accelerator built for the platform |
| **MXIF** | the tightly-coupled extension interface |
| **MEDS-S2** | reserved for the successor platform |

## Consequences

**Good:** the successor platform has an obvious name; papers can cite the platform and the core
separately; MEDS-V keeps its published identity.
**Bad:** "S1" appears in two forms (`MEDS-S1`, `S1-Core`) and people will occasionally conflate them.
**We accept:** a rename after RTL exists would be a 400-file diff, so this is settled now.
