// cat.dfy
// Formal specification and verified implementation of POSIX cat(1).
// Reference: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/cat.html
//
// Synopsis: cat [-u] [file...]
//
// Key behaviours formalised:
//   1. Reads files in sequence; writes their bytes to stdout in the same order.
//   2. No operands  =>  copies stdin to stdout verbatim.
//   3. Operand '-'  =>  reads remaining stdin at that point in the sequence.
//   4. '-' may appear multiple times; each reads remaining (possibly empty) stdin.
//   5. The -u flag does not change output bytes (only buffering, not content).
//   6. Exit 0 iff all inputs were read without error; exit >0 on any file error.
//   7. Stdout contains exactly the bytes from inputs — nothing else.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

// A byte is an integer in [0, 255].
type Byte = b: int | 0 <= b < 256 witness 0

// The file system maps file paths to their byte contents.
// A path absent from the map represents an inaccessible file (triggers an error).
type FileSystem = map<string, seq<Byte>>

// ---------------------------------------------------------------------------
// Specification (pure functional)
// ---------------------------------------------------------------------------

// Resolve a single file operand.
//
//   op == "-"  : consume all remaining stdin from stdin_pos.
//   op in fs   : return the named file's contents unchanged.
//   otherwise  : file not found — return empty bytes and signal an error.
//
// Returns (bytes_produced, new_stdin_pos, error_occurred).
function SpecProcessOperand(
  op: string,
  fs: FileSystem,
  stdin: seq<Byte>,
  stdin_pos: nat
): (seq<Byte>, nat, bool)
  requires stdin_pos <= |stdin|
  ensures SpecProcessOperand(op, fs, stdin, stdin_pos).1 <= |stdin|
  ensures SpecProcessOperand(op, fs, stdin, stdin_pos).1 >= stdin_pos
{
  if op == "-" then
    (stdin[stdin_pos..], |stdin|, false)    // read remaining stdin
  else if op in fs then
    (fs[op], stdin_pos, false)              // read named file
  else
    ([], stdin_pos, true)                   // file not found: error
}

// Resolve a sequence of operands, threading the stdin position through.
// Returns (stdout_bytes, final_stdin_pos, any_error).
function SpecProcessOperands(
  operands: seq<string>,
  fs: FileSystem,
  stdin: seq<Byte>,
  stdin_pos: nat
): (seq<Byte>, nat, bool)
  requires stdin_pos <= |stdin|
  ensures SpecProcessOperands(operands, fs, stdin, stdin_pos).1 <= |stdin|
  ensures SpecProcessOperands(operands, fs, stdin, stdin_pos).1 >= stdin_pos
{
  if |operands| == 0 then
    ([], stdin_pos, false)
  else
    var (bytes0, pos1, err0) := SpecProcessOperand(operands[0], fs, stdin, stdin_pos);
    var (bytes1, pos2, err1) := SpecProcessOperands(operands[1..], fs, stdin, pos1);
    (bytes0 + bytes1, pos2, err0 || err1)
}

// Top-level cat specification.
//   No operands : stdout = stdin, exit = 0.
//   Operands    : stdout = concatenation of resolved bytes; exit = 0 iff no errors.
function SpecCat(
  operands: seq<string>,
  fs: FileSystem,
  stdin: seq<Byte>
): (seq<Byte>, int)
{
  if |operands| == 0 then
    (stdin, 0)
  else
    var (output, _, had_error) := SpecProcessOperands(operands, fs, stdin, 0);
    (output, if had_error then 1 else 0)
}

// SpecCat with explicit -u flag.  The flag controls buffering, not content.
function SpecCatWithFlags(
  operands: seq<string>,
  fs: FileSystem,
  stdin: seq<Byte>,
  unbuffered: bool
): (seq<Byte>, int)
{
  SpecCat(operands, fs, stdin)
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

// Implement processing of a single operand.
// Postcondition: result equals SpecProcessOperand exactly.
method ImplProcessOperand(
  op: string,
  fs: FileSystem,
  stdin: seq<Byte>,
  stdin_pos: nat
) returns (bytes: seq<Byte>, new_stdin_pos: nat, error: bool)
  requires stdin_pos <= |stdin|
  ensures (bytes, new_stdin_pos, error) == SpecProcessOperand(op, fs, stdin, stdin_pos)
{
  if op == "-" {
    bytes         := stdin[stdin_pos..];
    new_stdin_pos := |stdin|;
    error         := false;
  } else if op in fs {
    bytes         := fs[op];
    new_stdin_pos := stdin_pos;
    error         := false;
  } else {
    bytes         := [];
    new_stdin_pos := stdin_pos;
    error         := true;
  }
}

// Implement processing of all operands in sequence.
// Recursive structure mirrors the spec; Dafny verifies postcondition directly.
method ImplProcessOperands(
  operands: seq<string>,
  fs: FileSystem,
  stdin: seq<Byte>,
  stdin_pos: nat
) returns (output: seq<Byte>, new_stdin_pos: nat, any_error: bool)
  requires stdin_pos <= |stdin|
  ensures (output, new_stdin_pos, any_error) ==
          SpecProcessOperands(operands, fs, stdin, stdin_pos)
{
  if |operands| == 0 {
    output        := [];
    new_stdin_pos := stdin_pos;
    any_error     := false;
  } else {
    var bytes0, pos1, err0 := ImplProcessOperand(operands[0], fs, stdin, stdin_pos);
    var bytes1, pos2, err1 := ImplProcessOperands(operands[1..], fs, stdin, pos1);
    output        := bytes0 + bytes1;
    new_stdin_pos := pos2;
    any_error     := err0 || err1;
  }
}

// Main cat implementation.
// Postcondition: (stdout, exit_code) == SpecCat(operands, fs, stdin).
method Cat(
  operands: seq<string>,
  fs: FileSystem,
  stdin: seq<Byte>
) returns (stdout: seq<Byte>, exit_code: int)
  ensures (stdout, exit_code) == SpecCat(operands, fs, stdin)
{
  if |operands| == 0 {
    stdout    := stdin;
    exit_code := 0;
  } else {
    var output, _, had_error := ImplProcessOperands(operands, fs, stdin, 0);
    stdout    := output;
    exit_code := if had_error then 1 else 0;
  }
}

// Cat with explicit -u flag.
// Postcondition: result matches SpecCatWithFlags (which ignores the flag).
method CatWithFlags(
  operands: seq<string>,
  fs: FileSystem,
  stdin: seq<Byte>,
  unbuffered: bool
) returns (stdout: seq<Byte>, exit_code: int)
  ensures (stdout, exit_code) == SpecCatWithFlags(operands, fs, stdin, unbuffered)
{
  stdout, exit_code := Cat(operands, fs, stdin);
}
