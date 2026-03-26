// CatIO.cs
// C# implementations of the {:extern "CatIO", ...} methods declared in extern.dfy.
//
// Actual type correspondence (Dafny 4.11, --unicode-char:false):
//   Dafny string      →  Dafny.ISequence<char>
//   Dafny int         →  System.Numerics.BigInteger   (int is arbitrary-precision)
//   Dafny Byte        →  BigInteger                   (Byte is a subset-type of int)
//   Dafny seq<Byte>   →  Dafny.ISequence<BigInteger>
//
// Calling convention: methods with a single "returns (x: T)" compile to a plain
// C# return value.  Methods with multiple return values use "out" parameters.

using System;
using System.IO;
using System.Linq;
using System.Numerics;

public class CatIO {

  // Read an entire file as seq<Byte>.  ok=false if unreadable.
  // Multiple return values → out parameters.
  public static void ReadFile(
      Dafny.ISequence<char> path,
      out Dafny.ISequence<BigInteger> bytes,
      out bool ok)
  {
    string p = new string(path.CloneAsArray());
    try {
      byte[] raw = File.ReadAllBytes(p);
      bytes = Dafny.Sequence<BigInteger>.FromArray(
          raw.Select(b => (BigInteger)b).ToArray());
      ok = true;
    } catch {
      bytes = Dafny.Sequence<BigInteger>.Empty;
      ok = false;
    }
  }

  // Drain all remaining stdin.  Single return value → plain C# return.
  public static Dafny.ISequence<BigInteger> ReadStdin() {
    using var ms = new MemoryStream();
    Console.OpenStandardInput().CopyTo(ms);
    byte[] raw = ms.ToArray();
    return Dafny.Sequence<BigInteger>.FromArray(
        raw.Select(b => (BigInteger)b).ToArray());
  }

  // Write seq<Byte> to stdout.
  public static void WriteBytes(Dafny.ISequence<BigInteger> bytes) {
    BigInteger[] arr = bytes.CloneAsArray();
    using Stream stdout = Console.OpenStandardOutput();
    foreach (BigInteger b in arr)
      stdout.WriteByte(checked((byte)(int)b));
  }

  // Write a diagnostic message to stderr.
  public static void WriteError(Dafny.ISequence<char> msg) {
    Console.Error.Write(new string(msg.CloneAsArray()));
  }

  // Exit the process with the given code.
  public static void Exit(BigInteger code) {
    System.Environment.Exit((int)code);
  }
}
