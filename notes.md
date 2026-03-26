# Design notes: Dafny cat

## Model

| Concept | Dafny representation |
|---|---|
| Byte | `type Byte = b: int \| 0 <= b < 256 witness 0` |
| File system | `type FileSystem = map<string, seq<Byte>>` |
| stdin | `seq<Byte>` parameter, consumed via `stdin_pos: nat` |
| stdout | `seq<Byte>` return value |
| exit code | `int` (0 = success, >0 = error) |

stdin is modelled as an immutable sequence; a `stdin_pos` index threads through `SpecProcessOperands` to record how much has been consumed. This captures the POSIX rule that `'-'` reads from where stdin was left off.

The `-u` (unbuffered) flag does not change output content (only I/O scheduling), so `SpecCatWithFlags` simply delegates to `SpecCat`, ignoring the flag. `LemmaUnbufferedFlagDoesNotChangeOutput` formalises this.

## Key lemmas proved

1. **LemmaNoOperandsOutputIsStdin** — no operands → stdout = stdin, exit 0
2. **LemmaStdinOperandYieldsFullStdin** — single `"-"` → stdout = stdin
3. **LemmaDashEquivalentToNoArgs** — `["-"]` ≡ `[]`
4. **LemmaTwoDashOperands** — second `"-"` sees empty stdin (already consumed)
5. **LemmaRegularFileOperand** — single accessible file → stdout = file content
6. **LemmaMissingFileErrors** — missing file → exit > 0
7. **LemmaOperandErrorIndependentOfPos** / **LemmaProcessOperandsErrorIndependentOfPos** — error flag depends only on accessibility, not stdin position
8. **LemmaProcessOperandsErrorCharacterisation** — error iff some operand is inaccessible
9. **LemmaExitCodeZeroIffAllAccessible** — exit 0 ↔ all operands are `"-"` or in fs
10. **LemmaUnbufferedFlagDoesNotChangeOutput** — `-u` flag is content-neutral
11. **LemmaOutputIsExactlyInputBytes** — stdout contains *exactly* the input bytes
12. **LemmaConcatenation** — output = concatenation of individual operand outputs

## Implementation structure

`ImplProcessOperand` → `ImplProcessOperands` (recursive, mirrors spec) → `Cat` → `CatWithFlags`

Each method carries a postcondition asserting exact equality with the corresponding spec function. Dafny discharges all proofs automatically once intermediate assertions guide the SMT solver through multi-level function unfolding.

## Proof hints needed

Dafny's SMT solver does not always simplify `[] + []` or `s + []` automatically when they arise inside unfolded recursive calls. Introducing `var e: seq<Byte> := []` and asserting `e + e == e` / `s + e == s` before the affected assertions resolves this.

## FFI / build architecture

```
extern.dfy  ──include──▶  cat.dfy        (verified spec + implementation)
    │
    │  {:extern "CatIO", ...}
    ▼
CatIO.cs                                  (C# I/O: ReadFile, ReadStdin, WriteBytes, WriteError)
```

`dafny build` (bundled .NET 8) generates `cat.cs` with the Dafny runtime inlined and
`cat.csproj` targeting `net8.0`.  The Makefile patches `<TargetFramework>` to match the
locally installed .NET SDK and re-runs `dotnet build`.

Type correspondence with `--unicode-char:false`:

| Dafny | C# |
|---|---|
| `string` | `Dafny.ISequence<char>` |
| `int` | `System.Numerics.BigInteger` |
| `Byte` (= subset int) | `BigInteger` |
| `seq<Byte>` | `Dafny.ISequence<BigInteger>` |
| `bool` | `bool` |

Single `returns (x: T)` → plain C# return value.
Multiple `returns` → `out` parameters.

## Dafny version

4.11.0 (verified: 30 assertions, 0 errors; 4 more in extern.dfy)
