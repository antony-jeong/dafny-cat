#!/usr/bin/env bash
# test.sh — compare ./cat against /bin/cat on macOS

cd "$(dirname "$0")"

OUR=./cat
REF=/bin/cat
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── helper ─────────────────────────────────────────────────────────────────
# cmp_cat DESC [STDIN_FILE] -- [cat args...]
#   Runs both cats (with optional stdin redirect from STDIN_FILE, or /dev/null).
#   Compares: stdout (byte-for-byte), exit-code class (0 vs >0).
#   Also checks that stderr is non-empty for our cat whenever ref cat writes one.
cmp_cat() {
  local desc="$1"; shift
  local stdin_file="/dev/null"
  if [[ "$1" != "--" ]]; then
    stdin_file="$1"; shift
  fi
  shift  # consume "--"

  "$OUR" "$@" < "$stdin_file" > "$TMP/our_out" 2> "$TMP/our_err"; local our_rc=$?
  "$REF" "$@" < "$stdin_file" > "$TMP/ref_out" 2> "$TMP/ref_err"; local ref_rc=$?

  local ok=1

  # stdout must match exactly
  if ! diff -q "$TMP/our_out" "$TMP/ref_out" > /dev/null 2>&1; then
    echo "FAIL [$desc] stdout differs"
    echo "  ref: $(xxd "$TMP/ref_out" | head -4)"
    echo "  our: $(xxd "$TMP/our_out" | head -4)"
    ok=0
  fi

  # both succeed or both fail
  local our_ok=0 ref_ok=0
  [[ $our_rc -eq 0 ]] && our_ok=1
  [[ $ref_rc -eq 0 ]] && ref_ok=1
  if [[ $our_ok -ne $ref_ok ]]; then
    echo "FAIL [$desc] exit-code class differs (ours=$our_rc ref=$ref_rc)"
    ok=0
  fi

  # if ref wrote to stderr, we should too
  if [[ -s "$TMP/ref_err" && ! -s "$TMP/our_err" ]]; then
    echo "FAIL [$desc] stderr: ref has diagnostic but ours is empty"
    ok=0
  fi

  if [[ $ok -eq 1 ]]; then
    echo "PASS [$desc]"
    ((PASS++)) || true
  else
    ((FAIL++)) || true
  fi
}

# ── fixtures ───────────────────────────────────────────────────────────────
F1="$TMP/file1.txt";   printf 'hello\nworld\n'        > "$F1"
F2="$TMP/file2.txt";   printf 'foo\nbar\nbaz\n'       > "$F2"
EMPTY="$TMP/empty";    :                              > "$EMPTY"
NL="$TMP/newlines";    printf '\n\n\n'                > "$NL"
BIN="$TMP/binary";     printf '\x00\x01\x7f\xfe\xff'  > "$BIN"
LARGE="$TMP/large";    yes "line" | head -10000       > "$LARGE"
STDIN="$TMP/stdin";    printf 'from_stdin\n'          > "$STDIN"
STDIN2="$TMP/stdin2";  printf 'middle\n'              > "$STDIN2"

# ── tests ──────────────────────────────────────────────────────────────────

# 1. No arguments: stdin → stdout
cmp_cat "no-args (stdin copy)" "$STDIN" --

# 2. Single file
cmp_cat "single file" -- "$F1"

# 3. Two files (concatenation)
cmp_cat "two files" -- "$F1" "$F2"

# 4. Empty file
cmp_cat "empty file" -- "$EMPTY"

# 5. File with only newlines
cmp_cat "newlines-only file" -- "$NL"

# 6. Binary content
cmp_cat "binary file" -- "$BIN"

# 7. Large file (10k lines)
cmp_cat "large file" -- "$LARGE"

# 8. '-' reads stdin
cmp_cat "dash reads stdin" "$STDIN" -- -

# 9. file, '-', file
cmp_cat "file dash file" "$STDIN2" -- "$F1" - "$F2"

# 10. '-' twice (second '-' sees empty stdin for regular-file stdin)
cmp_cat "dash dash" "$STDIN" -- - -

# 11. Missing file: exit > 0
cmp_cat "missing file" -- /no/such/file

# 12. Existing + missing + existing
cmp_cat "mixed missing" -- "$F1" /no/such/file "$F2"

# 13. -u flag produces same output
"$OUR" -u "$F1" > "$TMP/u_out"
"$OUR"    "$F1" > "$TMP/no_u_out"
if diff -q "$TMP/u_out" "$TMP/no_u_out" > /dev/null; then
  echo "PASS [-u same output as without -u]"; ((PASS++)) || true
else
  echo "FAIL [-u same output as without -u]"; ((FAIL++)) || true
fi

# 14. Same file listed twice
cmp_cat "same file twice" -- "$F1" "$F1"

# 15. Empty stdin, no operands
cmp_cat "empty stdin no-args" --

# 16. '-' with empty stdin
cmp_cat "dash empty stdin" -- -

# 17. Three files
cmp_cat "three files" -- "$F1" "$F2" "$F1"

# ── summary ────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
