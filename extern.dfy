// extern.dfy
// Entry point for the cat utility.
// Declares {:extern} I/O stubs (implemented in CatIO.cs) and wires them
// to the verified Cat implementation in cat.dfy.
//
// Build with:
//   dafny build --unicode-char:false --target:cs extern.dfy --input CatIO.cs -o cat

include "cat.dfy"

// ---------------------------------------------------------------------------
// External I/O declarations (implemented in CatIO.cs)
// ---------------------------------------------------------------------------

// Read a file's entire contents as seq<Byte>.
// Returns ok=false if the file cannot be opened or read.
method {:extern "CatIO", "ReadFile"} ExternReadFile(path: string)
  returns (bytes: seq<Byte>, ok: bool)

// Drain remaining stdin into seq<Byte>.
method {:extern "CatIO", "ReadStdin"} ExternReadStdin()
  returns (bytes: seq<Byte>)

// Write seq<Byte> to stdout.
method {:extern "CatIO", "WriteBytes"} ExternWriteBytes(bytes: seq<Byte>)

// Write a diagnostic message to stderr.
method {:extern "CatIO", "WriteError"} ExternWriteError(msg: string)

// Exit the process with the given code.
method {:extern "CatIO", "Exit"} ExternExit(code: int)

// ---------------------------------------------------------------------------
// Helper: build the FileSystem map by reading every named (non-"-") operand.
// Files that cannot be read are left absent from the map; Cat will flag them
// as errors.
// ---------------------------------------------------------------------------
method BuildFileSystem(operands: seq<string>)
  returns (fs: FileSystem)
  ensures forall p :: p in fs ==> p != "-"
{
  fs := map[];
  var i := 0;
  while i < |operands|
    invariant 0 <= i <= |operands|
    invariant forall p :: p in fs ==> p != "-"
    decreases |operands| - i
  {
    var op := operands[i];
    if op != "-" && op !in fs {
      var bytes, ok := ExternReadFile(op);
      if ok {
        fs := fs[op := bytes];
      }
      // !ok: leave op absent; Cat will detect the missing key and set exit > 0.
    }
    i := i + 1;
  }
}

// ---------------------------------------------------------------------------
// Helper: decide whether any operand is "-" (stdin placeholder).
// ---------------------------------------------------------------------------
ghost function HasDashOperand(operands: seq<string>): bool
{
  exists i :: 0 <= i < |operands| && operands[i] == "-"
}

method CheckHasDash(operands: seq<string>) returns (found: bool)
  ensures found == HasDashOperand(operands)
{
  found := false;
  var i := 0;
  while i < |operands|
    invariant 0 <= i <= |operands|
    invariant found == (exists j :: 0 <= j < i && operands[j] == "-")
    decreases |operands| - i
  {
    if operands[i] == "-" {
      found := true;
      return;
    }
    i := i + 1;
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
method Main(args: seq<string>)
{
  // Skip args[0] (program name); parse -u and collect operands.
  var suffix := if |args| > 0 then args[1..] else [];
  var unbuffered := false;
  var operands: seq<string> := [];
  var i := 0;
  while i < |suffix|
    invariant 0 <= i <= |suffix|
    decreases |suffix| - i
  {
    var arg := suffix[i];
    if arg == "-u" {
      unbuffered := true;
    } else {
      operands := operands + [arg];
    }
    i := i + 1;
  }

  // Read all named files into the FileSystem map.
  var fs := BuildFileSystem(operands);

  // Pre-read stdin only if at least one operand is "-", or there are no operands.
  var stdin_bytes: seq<Byte>;
  if |operands| == 0 {
    // No operands: stdin is the only input (SpecCat([], ...) = (stdin, 0)).
    stdin_bytes := ExternReadStdin();
  } else {
    var has_dash := CheckHasDash(operands);
    if has_dash {
      stdin_bytes := ExternReadStdin();
    } else {
      stdin_bytes := [];
    }
  }

  // Run the verified implementation.
  // Postcondition of CatWithFlags guarantees:
  //   (stdout_bytes, exit_code) == SpecCatWithFlags(operands, fs, stdin_bytes, unbuffered)
  var stdout_bytes, exit_code := CatWithFlags(operands, fs, stdin_bytes, unbuffered);

  ExternWriteBytes(stdout_bytes);
  if exit_code != 0 {
    ExternWriteError("cat: one or more files could not be read\n");
  }
  ExternExit(exit_code);
}
