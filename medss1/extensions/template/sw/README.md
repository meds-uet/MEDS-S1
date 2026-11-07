# Toolchain path

Minimum viable: a `.insn` macro plus an inline-asm wrapper header, so software can use the
instruction without a patched compiler.

```c
// <name>.h
#define MEDS_X_FOO(rd, rs1, rs2) \
    asm volatile(".insn r 0x0B, 0x0, 0x00, %0, %1, %2" \
                 : "=r"(rd) : "r"(rs1), "r"(rs2))
```

A GCC/LLVM builtin is required only once the extension is marked `stable`.
