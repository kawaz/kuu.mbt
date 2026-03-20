#!/usr/bin/env bash
# kuu-cli compatibility test against WASM bridge (test.mjs)
# Verifies that kuu-cli (native binary) produces the same JSON output
# as the WASM bridge kuu_parse function.
#
# Usage:
#   bash src/cli/test_compat.sh
#   bash src/cli/test_compat.sh --verbose   # show all test details

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KUU_CLI="$PROJECT_ROOT/_build/native/debug/build/cli/cli.exe"

PASS=0
FAIL=0
SKIP=0
TOTAL=0
VERBOSE="${1:-}"
FAILURES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check prerequisites
if [[ ! -x "$KUU_CLI" ]]; then
  echo "ERROR: kuu-cli binary not found at $KUU_CLI"
  echo "Build it first: moon build --target native"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required for JSON normalization"
  exit 1
fi

# Normalize JSON for comparison: sort keys, compact
normalize() {
  jq -cS 2>/dev/null || echo "INVALID_JSON"
}

# Run a single parse test case
# Usage: test_parse "name" 'input_json' 'expected_json_or_jq_check'
# If expected starts with "jq:", use jq expression for validation
test_parse() {
  local name="$1"
  local input="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))

  local actual
  actual=$(echo "$input" | "$KUU_CLI" parse - 2>/dev/null) || true

  local actual_norm expected_norm
  actual_norm=$(echo "$actual" | normalize)
  expected_norm=$(echo "$expected" | normalize)

  if [[ "$actual_norm" == "$expected_norm" ]]; then
    PASS=$((PASS + 1))
    if [[ "$VERBOSE" == "--verbose" ]]; then
      echo -e "${GREEN}PASS${NC}: $name"
    fi
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$name")
    echo -e "${RED}FAIL${NC}: $name"
    echo "  expected: $expected_norm"
    echo "  actual:   $actual_norm"
  fi
}

# Run a parse test and validate with jq expression
# Usage: test_parse_jq "name" 'input_json' 'jq_filter' 'expected_value'
test_parse_jq() {
  local name="$1"
  local input="$2"
  local jq_filter="$3"
  local expected_value="$4"
  TOTAL=$((TOTAL + 1))

  local actual
  actual=$(echo "$input" | "$KUU_CLI" parse - 2>/dev/null) || true

  local extracted
  extracted=$(echo "$actual" | jq -r "$jq_filter" 2>/dev/null) || extracted="JQ_ERROR"

  if [[ "$extracted" == "$expected_value" ]]; then
    PASS=$((PASS + 1))
    if [[ "$VERBOSE" == "--verbose" ]]; then
      echo -e "${GREEN}PASS${NC}: $name"
    fi
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$name")
    echo -e "${RED}FAIL${NC}: $name"
    echo "  jq filter: $jq_filter"
    echo "  expected: $expected_value"
    echo "  extracted: $extracted"
    echo "  full output: $actual"
  fi
}

echo -e "${CYAN}=== kuu-cli compatibility test ===${NC}"
echo "Binary: $KUU_CLI"
echo ""

# ============================================================
# Test 1: Simple flag + string opt
# ============================================================
test_parse "Test 1: Simple flag + string" \
  '{"description":"My CLI","opts":[{"kind":"flag","name":"verbose","shorts":"v","description":"Verbose output"},{"kind":"string","name":"host","default":"localhost","description":"Host"},{"kind":"int","name":"port","default":8080,"description":"Port"}],"args":["--verbose","--host","example.com"]}' \
  '{"ok":true,"values":{"verbose":true,"host":"example.com","port":8080}}'

# ============================================================
# Test 2: Positional + rest
# ============================================================
test_parse "Test 2: Positional + rest" \
  '{"opts":[{"kind":"positional","name":"file","description":"Input file"},{"kind":"rest","name":"args","description":"Extra args"}],"args":["input.txt","extra1","extra2"]}' \
  '{"ok":true,"values":{"file":"input.txt","args":["extra1","extra2"]}}'

# ============================================================
# Test 3: Subcommand
# ============================================================
test_parse "Test 3: Subcommand" \
  '{"opts":[{"kind":"flag","name":"verbose","shorts":"v","global":true},{"kind":"command","name":"serve","description":"Start server","opts":[{"kind":"int","name":"port","default":3000,"description":"Port"}]}],"args":["--verbose","serve","--port","9090"]}' \
  '{"ok":true,"values":{"verbose":true},"command":{"name":"serve","values":{"port":9090}}}'

# ============================================================
# Test 4: Help request
# ============================================================
test_parse_jq "Test 4: Help request" \
  '{"description":"Test CLI","opts":[{"kind":"flag","name":"verbose","description":"Verbose"}],"args":["--help"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 4b: Help request - help_requested" \
  '{"description":"Test CLI","opts":[{"kind":"flag","name":"verbose","description":"Verbose"}],"args":["--help"]}' \
  '.help_requested' \
  'true'

test_parse_jq "Test 4c: Help request - contains --verbose" \
  '{"description":"Test CLI","opts":[{"kind":"flag","name":"verbose","description":"Verbose"}],"args":["--help"]}' \
  '.help | contains("--verbose")' \
  'true'

# ============================================================
# Test 5: Parse error - unknown option
# ============================================================
test_parse_jq "Test 5: Parse error - unknown option" \
  '{"opts":[],"args":["--unknown"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 5b: Parse error - kind" \
  '{"opts":[],"args":["--unknown"]}' \
  '.kind' \
  'UnknownOption'

# ============================================================
# Test 6: Count + short combine
# ============================================================
test_parse "Test 6: Count + short combine" \
  '{"opts":[{"kind":"count","name":"verbose","shorts":"v","description":"Verbosity"}],"args":["-vvv"]}' \
  '{"ok":true,"values":{"verbose":3}}'

# ============================================================
# Test 7: append_string
# ============================================================
test_parse "Test 7: Append string" \
  '{"opts":[{"kind":"append_string","name":"tag","description":"Tags"}],"args":["--tag","a","--tag","b","--tag","c"]}' \
  '{"ok":true,"values":{"tag":["a","b","c"]}}'

# ============================================================
# Test 8: String with choices
# ============================================================
test_parse "Test 8: String with choices" \
  '{"opts":[{"kind":"string","name":"color","default":"auto","choices":["auto","always","never"]}],"args":["--color","always"]}' \
  '{"ok":true,"values":{"color":"always"}}'

# ============================================================
# Test 9: Explicit version 1
# ============================================================
test_parse "Test 9: Version 1 explicit" \
  '{"version":1,"opts":[{"kind":"flag","name":"verbose","description":"Verbose"}],"args":["--verbose"]}' \
  '{"ok":true,"values":{"verbose":true}}'

# ============================================================
# Test 10: Unsupported version
# ============================================================
test_parse "Test 10: Unsupported version" \
  '{"version":2,"opts":[],"args":[]}' \
  '{"ok":false,"error":"unsupported schema version: 2"}'

# ============================================================
# Test 11: Unknown opt kind
# ============================================================
test_parse "Test 11: Unknown opt kind" \
  '{"opts":[{"kind":"unknown_kind_xyz","name":"flag1"}],"args":[]}' \
  '{"ok":false,"error":"unknown opt kind: unknown_kind_xyz"}'

# ============================================================
# Test 12: Missing name in opt
# ============================================================
test_parse "Test 12: Missing name in opt" \
  '{"opts":[{"kind":"flag"}],"args":[]}' \
  '{"ok":false,"error":"opt definition missing '\''name'\''"}'

# ============================================================
# Test 13: Non-string in args
# ============================================================
test_parse "Test 13: Non-string in args" \
  '{"opts":[],"args":["--verbose",42]}' \
  '{"ok":false,"error":"args must be an array of strings"}'

# ============================================================
# Test 14: Non-object element in opts
# ============================================================
test_parse "Test 14: Non-object element in opts" \
  '{"opts":[{"kind":"flag","name":"verbose"},"not-an-object"],"args":[]}' \
  '{"ok":false,"error":"each element in '\''opts'\'' must be an object"}'

# ============================================================
# Test 15: opts is not an array (string)
# ============================================================
test_parse "Test 15: opts is not an array" \
  '{"opts":"not-an-array","args":[]}' \
  '{"ok":false,"error":"'\''opts'\'' must be an array"}'

# ============================================================
# Test 16: opts is a number
# ============================================================
test_parse "Test 16: opts is a number" \
  '{"opts":42,"args":[]}' \
  '{"ok":false,"error":"'\''opts'\'' must be an array"}'

# ============================================================
# Test 17: Flag with variations (--force-wall)
# ============================================================
test_parse "Test 17: Flag with variations" \
  '{"opts":[{"kind":"flag","name":"wall","variation_false":"no","variation_toggle":"toggle","variation_true":"force","variation_reset":"reset","variation_unset":"unset"}],"args":["--force-wall"]}' \
  '{"ok":true,"values":{"wall":true}}'

# ============================================================
# Test 18: Flag variation_false (--no-wall)
# ============================================================
test_parse "Test 18: Flag variation_false" \
  '{"opts":[{"kind":"flag","name":"wall","default":true,"variation_false":"no"}],"args":["--no-wall"]}' \
  '{"ok":true,"values":{"wall":false}}'

# ============================================================
# Test 19: String opt with variation_reset
# ============================================================
test_parse "Test 19: String opt variation_reset" \
  '{"opts":[{"kind":"string","name":"color","default":"auto","variation_reset":"reset"}],"args":["--color","always","--reset-color"]}' \
  '{"ok":true,"values":{"color":"auto"}}'

# ============================================================
# Test 20: Count with variation_unset
# ============================================================
test_parse "Test 20: Count variation_unset" \
  '{"opts":[{"kind":"count","name":"verbose","shorts":"v","variation_unset":"no"}],"args":["-vvv","--no-verbose"]}' \
  '{"ok":true,"values":{"verbose":0}}'

# ============================================================
# Test 21: String with implicit_value
# ============================================================
test_parse "Test 21: String implicit_value" \
  '{"opts":[{"kind":"string","name":"color","default":"auto","implicit_value":"always"}],"args":["--color"]}' \
  '{"ok":true,"values":{"color":"always"}}'

# ============================================================
# Test 22: Int with implicit_value
# ============================================================
test_parse "Test 22: Int implicit_value" \
  '{"opts":[{"kind":"int","name":"verbosity","default":0,"implicit_value":3}],"args":["--verbosity"]}' \
  '{"ok":true,"values":{"verbosity":3}}'

# ============================================================
# Test 23: Dashdash kind
# ============================================================
test_parse "Test 23: Dashdash kind" \
  '{"opts":[{"kind":"flag","name":"verbose"},{"kind":"dashdash"}],"args":["--verbose","--","extra1","extra2"]}' \
  '{"ok":true,"values":{"verbose":true,"--":["extra1","extra2"]}}'

# ============================================================
# Test 24: require_cmd at top level
# ============================================================
test_parse_jq "Test 24: require_cmd top level" \
  '{"opts":[{"kind":"command","name":"sub1","opts":[]}],"require_cmd":true,"args":[]}' \
  '.ok' \
  'false'

test_parse_jq "Test 24b: require_cmd kind" \
  '{"opts":[{"kind":"command","name":"sub1","opts":[]}],"require_cmd":true,"args":[]}' \
  '.kind' \
  'MissingSubcommand'

# ============================================================
# Test 25: require_cmd inside command
# ============================================================
test_parse_jq "Test 25: require_cmd inside command" \
  '{"opts":[{"kind":"command","name":"parent","require_cmd":true,"opts":[{"kind":"command","name":"child","opts":[]}]}],"args":["parent"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 25b: require_cmd inside command kind" \
  '{"opts":[{"kind":"command","name":"parent","require_cmd":true,"opts":[{"kind":"command","name":"child","opts":[]}]}],"args":["parent"]}' \
  '.kind' \
  'MissingSubcommand'

# ============================================================
# Test 26: Exclusive constraint
# ============================================================
test_parse_jq "Test 26: Exclusive constraint" \
  '{"opts":[{"kind":"flag","name":"shared"},{"kind":"flag","name":"static"}],"exclusive":[["shared","static"]],"args":["--shared","--static"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 26b: Exclusive kind" \
  '{"opts":[{"kind":"flag","name":"shared"},{"kind":"flag","name":"static"}],"exclusive":[["shared","static"]],"args":["--shared","--static"]}' \
  '.kind' \
  'ArgumentConflict'

# ============================================================
# Test 27: Required constraint
# ============================================================
test_parse_jq "Test 27: Required constraint" \
  '{"opts":[{"kind":"string","name":"filename","default":""},{"kind":"string","name":"output","default":""}],"required":["filename"],"args":[]}' \
  '.ok' \
  'false'

test_parse_jq "Test 27b: Required kind" \
  '{"opts":[{"kind":"string","name":"filename","default":""},{"kind":"string","name":"output","default":""}],"required":["filename"],"args":[]}' \
  '.kind' \
  'MissingRequired'

# ============================================================
# Test 28: Command aliases
# ============================================================
test_parse "Test 28: Command aliases" \
  '{"opts":[{"kind":"command","name":"checkout","aliases":["co"],"opts":[{"kind":"positional","name":"branch"}]}],"args":["co","main"]}' \
  '{"ok":true,"command":{"name":"checkout","values":{"branch":"main"}},"values":{}}'

# ============================================================
# Test 29: Serial kind
# ============================================================
test_parse "Test 29: Serial kind" \
  '{"opts":[{"kind":"serial","opts":[{"kind":"positional","name":"src"},{"kind":"positional","name":"dst"}]}],"args":["a.txt","b.txt"]}' \
  '{"ok":true,"values":{"src":"a.txt","dst":"b.txt"}}'

# ============================================================
# Test 30: Post filter trim
# ============================================================
test_parse "Test 30: Post filter trim" \
  '{"opts":[{"kind":"string","name":"name","default":"","post":"trim"}],"args":["--name","  hello  "]}' \
  '{"ok":true,"values":{"name":"hello"}}'

# ============================================================
# Test 31: Post filter non_empty
# ============================================================
test_parse_jq "Test 31: Post filter non_empty" \
  '{"opts":[{"kind":"string","name":"name","default":"fallback","post":"non_empty"}],"args":["--name",""]}' \
  '.ok' \
  'false'

test_parse_jq "Test 31b: Post filter non_empty kind" \
  '{"opts":[{"kind":"string","name":"name","default":"fallback","post":"non_empty"}],"args":["--name",""]}' \
  '.kind' \
  'InvalidValue'

# ============================================================
# Test 32: Post filter in_range
# ============================================================
test_parse "Test 32: Post filter in_range" \
  '{"opts":[{"kind":"int","name":"v","default":0,"post":{"in_range":[0,9]}}],"args":["--v","5"]}' \
  '{"ok":true,"values":{"v":5}}'

# ============================================================
# Test 33: Post filter in_range error
# ============================================================
test_parse_jq "Test 33: Post filter in_range error" \
  '{"opts":[{"kind":"int","name":"v","default":0,"post":{"in_range":[0,9]}}],"args":["--v","10"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 33b: Post filter in_range error kind" \
  '{"opts":[{"kind":"int","name":"v","default":0,"post":{"in_range":[0,9]}}],"args":["--v","10"]}' \
  '.kind' \
  'InvalidValue'

# ============================================================
# Test 34: Float kind basic
# ============================================================
test_parse "Test 34: Float kind basic" \
  '{"opts":[{"kind":"float","name":"rate","default":1.0,"description":"Rate"}],"args":["--rate","3.14"]}' \
  '{"ok":true,"values":{"rate":3.14}}'

# ============================================================
# Test 35: Float kind default
# ============================================================
test_parse "Test 35: Float kind default" \
  '{"opts":[{"kind":"float","name":"rate","default":2.5}],"args":[]}' \
  '{"ok":true,"values":{"rate":2.5}}'

# ============================================================
# Test 36: Float kind with float_in_range post filter
# ============================================================
test_parse "Test 36: Float float_in_range post" \
  '{"opts":[{"kind":"float","name":"rate","default":0.0,"post":{"float_in_range":[0.0,1.0]}}],"args":["--rate","0.5"]}' \
  '{"ok":true,"values":{"rate":0.5}}'

# ============================================================
# Test 37: Float kind float_in_range error
# ============================================================
test_parse_jq "Test 37: Float float_in_range error" \
  '{"opts":[{"kind":"float","name":"rate","default":0.0,"post":{"float_in_range":[0.0,1.0]}}],"args":["--rate","1.5"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 37b: Float float_in_range error kind" \
  '{"opts":[{"kind":"float","name":"rate","default":0.0,"post":{"float_in_range":[0.0,1.0]}}],"args":["--rate","1.5"]}' \
  '.kind' \
  'InvalidValue'

# ============================================================
# Test 38: Append float kind
# ============================================================
test_parse "Test 38: Append float kind" \
  '{"opts":[{"kind":"append_float","name":"score","description":"Scores"}],"args":["--score","1.5","--score","2.7"]}' \
  '{"ok":true,"values":{"score":[1.5,2.7]}}'

# ============================================================
# Test 39: Append float kind empty
# ============================================================
test_parse "Test 39: Append float kind empty" \
  '{"opts":[{"kind":"append_float","name":"score"}],"args":[]}' \
  '{"ok":true,"values":{"score":[]}}'

# ============================================================
# Test 40: Float kind invalid value
# ============================================================
test_parse_jq "Test 40: Float kind invalid value" \
  '{"opts":[{"kind":"float","name":"rate","default":0.0}],"args":["--rate","abc"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 40b: Float kind invalid kind" \
  '{"opts":[{"kind":"float","name":"rate","default":0.0}],"args":["--rate","abc"]}' \
  '.kind' \
  'InvalidValue'

# ============================================================
# Test 41: Float kind with implicit_value
# ============================================================
test_parse "Test 41: Float implicit_value" \
  '{"opts":[{"kind":"float","name":"threshold","default":0.0,"implicit_value":0.5}],"args":["--threshold"]}' \
  '{"ok":true,"values":{"threshold":0.5}}'

# ============================================================
# Test 42: Boolean kind basic
# ============================================================
test_parse "Test 42: Boolean kind basic" \
  '{"opts":[{"kind":"boolean","name":"debug","description":"Debug mode"}],"args":["--debug","true"]}' \
  '{"ok":true,"values":{"debug":true}}'

# ============================================================
# Test 43: Boolean kind false (off)
# ============================================================
test_parse "Test 43: Boolean kind false" \
  '{"opts":[{"kind":"boolean","name":"debug"}],"args":["--debug","off"]}' \
  '{"ok":true,"values":{"debug":false}}'

# ============================================================
# Test 44: Boolean kind default
# ============================================================
test_parse "Test 44: Boolean kind default" \
  '{"opts":[{"kind":"boolean","name":"debug"}],"args":[]}' \
  '{"ok":true,"values":{"debug":false}}'

# ============================================================
# Test 45: Boolean kind invalid
# ============================================================
test_parse_jq "Test 45: Boolean kind invalid" \
  '{"opts":[{"kind":"boolean","name":"debug"}],"args":["--debug","maybe"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 45b: Boolean kind invalid kind" \
  '{"opts":[{"kind":"boolean","name":"debug"}],"args":["--debug","maybe"]}' \
  '.kind' \
  'InvalidValue'

# ============================================================
# Test 46: Env sets value when CLI arg not provided
# ============================================================
test_parse "Test 46: Env sets value" \
  '{"opts":[{"kind":"string","name":"host","default":"localhost","env":"HOST"}],"args":[],"env":{"HOST":"env-host.example.com"}}' \
  '{"ok":true,"values":{"host":"env-host.example.com"}}'

# ============================================================
# Test 47: CLI arg overrides env
# ============================================================
test_parse "Test 47: CLI overrides env" \
  '{"opts":[{"kind":"string","name":"host","default":"localhost","env":"HOST"}],"args":["--host","cli-host"],"env":{"HOST":"env-host"}}' \
  '{"ok":true,"values":{"host":"cli-host"}}'

# ============================================================
# Test 48: Env not provided uses default
# ============================================================
test_parse "Test 48: Env absent uses default" \
  '{"opts":[{"kind":"string","name":"host","default":"localhost","env":"HOST"}],"args":[],"env":{}}' \
  '{"ok":true,"values":{"host":"localhost"}}'

# ============================================================
# Test 49: Env with flag (true/1)
# ============================================================
test_parse "Test 49: Env flag true" \
  '{"opts":[{"kind":"flag","name":"verbose","env":"VERBOSE"}],"args":[],"env":{"VERBOSE":"1"}}' \
  '{"ok":true,"values":{"verbose":true}}'

# ============================================================
# Test 50: Env without env field in schema
# ============================================================
test_parse "Test 50: Env field absent in schema" \
  '{"opts":[{"kind":"string","name":"host","default":"localhost"}],"args":[],"env":{"HOST":"should-not-apply"}}' \
  '{"ok":true,"values":{"host":"localhost"}}'

# ============================================================
# Test 51: At least one passes when one is set
# ============================================================
test_parse "Test 51: At least one passes" \
  '{"opts":[{"kind":"flag","name":"json"},{"kind":"flag","name":"csv"}],"at_least_one":[["json","csv"]],"args":["--json"]}' \
  '{"ok":true,"values":{"json":true,"csv":false}}'

# ============================================================
# Test 52: At least one error when none set
# ============================================================
test_parse_jq "Test 52: At least one error" \
  '{"opts":[{"kind":"flag","name":"json"},{"kind":"flag","name":"csv"}],"at_least_one":[["json","csv"]],"args":[]}' \
  '.ok' \
  'false'

test_parse_jq "Test 52b: At least one error kind" \
  '{"opts":[{"kind":"flag","name":"json"},{"kind":"flag","name":"csv"}],"at_least_one":[["json","csv"]],"args":[]}' \
  '.kind' \
  'AtLeastOneRequired'

# ============================================================
# Test 53: At least one passes when all set
# ============================================================
test_parse_jq "Test 53: At least one all set" \
  '{"opts":[{"kind":"flag","name":"json"},{"kind":"flag","name":"csv"}],"at_least_one":[["json","csv"]],"args":["--json","--csv"]}' \
  '.ok' \
  'true'

# ============================================================
# Test 54: Requires passes when both set
# ============================================================
test_parse "Test 54: Requires passes" \
  '{"opts":[{"kind":"string","name":"key_file","default":""},{"kind":"string","name":"output","default":""}],"requires":[{"source":"key_file","target":"output"}],"args":["--key_file","id_rsa","--output","result.txt"]}' \
  '{"ok":true,"values":{"key_file":"id_rsa","output":"result.txt"}}'

# ============================================================
# Test 55: Requires error when source set but target not
# ============================================================
test_parse_jq "Test 55: Requires error" \
  '{"opts":[{"kind":"string","name":"key_file","default":""},{"kind":"string","name":"output","default":""}],"requires":[{"source":"key_file","target":"output"}],"args":["--key_file","id_rsa"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 55b: Requires error kind" \
  '{"opts":[{"kind":"string","name":"key_file","default":""},{"kind":"string","name":"output","default":""}],"requires":[{"source":"key_file","target":"output"}],"args":["--key_file","id_rsa"]}' \
  '.kind' \
  'DependencyMissing'

# ============================================================
# Test 56: Requires passes when source not set
# ============================================================
test_parse_jq "Test 56: Requires passes source unset" \
  '{"opts":[{"kind":"string","name":"key_file","default":""},{"kind":"string","name":"output","default":""}],"requires":[{"source":"key_file","target":"output"}],"args":[]}' \
  '.ok' \
  'true'

# ============================================================
# Test 57: Requires with custom message
# ============================================================
test_parse_jq "Test 57: Requires custom msg" \
  '{"opts":[{"kind":"string","name":"key_file","default":""},{"kind":"string","name":"output","default":""}],"requires":[{"source":"key_file","target":"output","msg":"--key_file requires --output to be specified"}],"args":["--key_file","id_rsa"]}' \
  '.error' \
  '--key_file requires --output to be specified'

test_parse_jq "Test 57b: Requires custom msg kind" \
  '{"opts":[{"kind":"string","name":"key_file","default":""},{"kind":"string","name":"output","default":""}],"requires":[{"source":"key_file","target":"output","msg":"--key_file requires --output to be specified"}],"args":["--key_file","id_rsa"]}' \
  '.kind' \
  'DependencyMissing'

# ============================================================
# Test 58: Deprecated records warning when used
# ============================================================
test_parse "Test 58: Deprecated records warning" \
  '{"opts":[{"kind":"string","name":"output","default":""},{"kind":"deprecated","name":"--out","target":"output","msg":"Use --output instead"}],"args":["--out","file.txt"]}' \
  '{"ok":true,"values":{"output":"file.txt"},"deprecated_warnings":[{"name":"--out","msg":"Use --output instead"}]}'

# ============================================================
# Test 59: Deprecated not used - no warnings
# ============================================================
test_parse "Test 59: Deprecated not used" \
  '{"opts":[{"kind":"string","name":"output","default":""},{"kind":"deprecated","name":"--out","target":"output","msg":"Use --output instead"}],"args":["--output","file.txt"]}' \
  '{"ok":true,"values":{"output":"file.txt"}}'

# ============================================================
# Test 60: Deprecated target not found
# ============================================================
test_parse "Test 60: Deprecated target not found" \
  '{"opts":[{"kind":"deprecated","name":"--old","target":"nonexistent","msg":"gone"}],"args":[]}' \
  '{"ok":false,"error":"deprecated target not found: nonexistent"}'

# ============================================================
# Test 61: Deprecated with flag target
# ============================================================
test_parse "Test 61: Deprecated flag" \
  '{"opts":[{"kind":"flag","name":"verbose"},{"kind":"deprecated","name":"--verb","target":"verbose","msg":"Use --verbose"}],"args":["--verb"]}' \
  '{"ok":true,"values":{"verbose":true},"deprecated_warnings":[{"name":"--verb","msg":"Use --verbose"}]}'

# ============================================================
# Test 62: Tip field with typo suggestion
# ============================================================
test_parse_jq "Test 62: Error tip with typo" \
  '{"opts":[{"kind":"int","name":"port","default":8080}],"args":["--prot"]}' \
  '.kind' \
  'UnknownOption'

test_parse_jq "Test 62b: Error tip value" \
  '{"opts":[{"kind":"int","name":"port","default":8080}],"args":["--prot"]}' \
  '.tip' \
  '--port'

# ============================================================
# Test 63: Schema validation errors have no kind/tip
# ============================================================
test_parse_jq "Test 63: Schema error no kind" \
  '{"opts":[{"kind":"flag"}],"args":[]}' \
  '.kind' \
  'null'

test_parse_jq "Test 63b: Schema error no tip" \
  '{"opts":[{"kind":"flag"}],"args":[]}' \
  '.tip' \
  'null'

# ============================================================
# Test 64: Clone basic
# ============================================================
test_parse "Test 64: Clone basic" \
  '{"opts":[{"kind":"int","name":"port","default":8080},{"kind":"clone","name":"clone_port","clone_of":"port"}],"args":["--port","3000","--clone_port","9090"]}' \
  '{"ok":true,"values":{"port":3000,"clone_port":9090}}'

# ============================================================
# Test 65: Clone uses target default
# ============================================================
test_parse "Test 65: Clone default" \
  '{"opts":[{"kind":"int","name":"port","default":8080},{"kind":"clone","name":"clone_port","clone_of":"port"}],"args":["--port","3000"]}' \
  '{"ok":true,"values":{"port":3000,"clone_port":8080}}'

# ============================================================
# Test 66: Clone of string opt
# ============================================================
test_parse "Test 66: Clone string" \
  '{"opts":[{"kind":"string","name":"host","default":"localhost"},{"kind":"clone","name":"alt_host","clone_of":"host"}],"args":["--alt_host","example.com"]}' \
  '{"ok":true,"values":{"host":"localhost","alt_host":"example.com"}}'

# ============================================================
# Test 67: Clone of flag
# ============================================================
test_parse "Test 67: Clone flag" \
  '{"opts":[{"kind":"flag","name":"verbose"},{"kind":"clone","name":"debug_verbose","clone_of":"verbose"}],"args":["--debug_verbose"]}' \
  '{"ok":true,"values":{"verbose":false,"debug_verbose":true}}'

# ============================================================
# Test 68: Clone target not found
# ============================================================
test_parse "Test 68: Clone target not found" \
  '{"opts":[{"kind":"clone","name":"orphan","clone_of":"nonexistent"}],"args":[]}' \
  '{"ok":false,"error":"clone target not found: nonexistent"}'

# ============================================================
# Test 69: Link basic
# ============================================================
test_parse "Test 69: Link basic" \
  '{"opts":[{"kind":"int","name":"verbose_level","default":0},{"kind":"int","name":"debug_level","default":0}],"links":[{"source":"verbose_level","target":"debug_level"}],"args":["--verbose_level","3"]}' \
  '{"ok":true,"values":{"verbose_level":3,"debug_level":3}}'

# ============================================================
# Test 70: Link not triggered when source unset
# ============================================================
test_parse "Test 70: Link source unset" \
  '{"opts":[{"kind":"int","name":"verbose_level","default":0},{"kind":"int","name":"debug_level","default":5}],"links":[{"source":"verbose_level","target":"debug_level"}],"args":[]}' \
  '{"ok":true,"values":{"verbose_level":0,"debug_level":5}}'

# ============================================================
# Test 71: Link with propagate_set
# ============================================================
test_parse "Test 71: Link propagate_set" \
  '{"opts":[{"kind":"string","name":"src","default":""},{"kind":"string","name":"dst","default":""}],"links":[{"source":"src","target":"dst","propagate_set":true}],"required":["dst"],"args":["--src","hello"]}' \
  '{"ok":true,"values":{"src":"hello","dst":"hello"}}'

# ============================================================
# Test 72: Link without propagate_set required fails
# ============================================================
test_parse_jq "Test 72: Link no propagate_set required fails" \
  '{"opts":[{"kind":"string","name":"src","default":""},{"kind":"string","name":"dst","default":""}],"links":[{"source":"src","target":"dst"}],"required":["dst"],"args":["--src","hello"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 72b: Link no propagate_set kind" \
  '{"opts":[{"kind":"string","name":"src","default":""},{"kind":"string","name":"dst","default":""}],"links":[{"source":"src","target":"dst"}],"required":["dst"],"args":["--src","hello"]}' \
  '.kind' \
  'MissingRequired'

# ============================================================
# Test 73: Link source not found
# ============================================================
test_parse "Test 73: Link source not found" \
  '{"opts":[{"kind":"string","name":"dst","default":""}],"links":[{"source":"nonexistent","target":"dst"}],"args":[]}' \
  '{"ok":false,"error":"link source not found: nonexistent"}'

# ============================================================
# Test 74: Link target not found
# ============================================================
test_parse "Test 74: Link target not found" \
  '{"opts":[{"kind":"string","name":"src","default":""}],"links":[{"source":"src","target":"nonexistent"}],"args":[]}' \
  '{"ok":false,"error":"link target not found: nonexistent"}'

# ============================================================
# Test 75: Link type mismatch
# ============================================================
test_parse "Test 75: Link type mismatch" \
  '{"opts":[{"kind":"int","name":"count","default":0},{"kind":"string","name":"name","default":""}],"links":[{"source":"count","target":"name"}],"args":[]}' \
  '{"ok":false,"error":"link type mismatch: count and name must be the same type"}'

# ============================================================
# Test 76: Adjust with in_range filter
# ============================================================
test_parse "Test 76: Adjust in_range" \
  '{"opts":[{"kind":"int","name":"port","default":8080}],"adjusts":[{"target":"port","filter":{"in_range":[1,65535]}}],"args":["--port","3000"]}' \
  '{"ok":true,"values":{"port":3000}}'

# ============================================================
# Test 77: Adjust in_range error
# ============================================================
test_parse_jq "Test 77: Adjust in_range error" \
  '{"opts":[{"kind":"int","name":"port","default":8080}],"adjusts":[{"target":"port","filter":{"in_range":[1,65535]}}],"args":["--port","0"]}' \
  '.ok' \
  'false'

test_parse_jq "Test 77b: Adjust in_range error kind" \
  '{"opts":[{"kind":"int","name":"port","default":8080}],"adjusts":[{"target":"port","filter":{"in_range":[1,65535]}}],"args":["--port","0"]}' \
  '.kind' \
  'InvalidValue'

# ============================================================
# Test 78: Adjust with clamp filter
# ============================================================
test_parse "Test 78: Adjust clamp" \
  '{"opts":[{"kind":"int","name":"port","default":8080}],"adjusts":[{"target":"port","filter":{"clamp":[1,65535]}}],"args":["--port","0"]}' \
  '{"ok":true,"values":{"port":1}}'

# ============================================================
# Test 79: Adjust with trim filter
# ============================================================
test_parse "Test 79: Adjust trim" \
  '{"opts":[{"kind":"string","name":"name","default":""}],"adjusts":[{"target":"name","filter":"trim"}],"args":["--name","  hello  "]}' \
  '{"ok":true,"values":{"name":"hello"}}'

# ============================================================
# Test 80: Adjust with non_empty filter
# ============================================================
test_parse_jq "Test 80: Adjust non_empty" \
  '{"opts":[{"kind":"string","name":"name","default":""}],"adjusts":[{"target":"name","filter":"non_empty"}],"args":["--name",""]}' \
  '.ok' \
  'false'

test_parse_jq "Test 80b: Adjust non_empty kind" \
  '{"opts":[{"kind":"string","name":"name","default":""}],"adjusts":[{"target":"name","filter":"non_empty"}],"args":["--name",""]}' \
  '.kind' \
  'InvalidValue'

# ============================================================
# Test 81: Adjust with float_in_range
# ============================================================
test_parse "Test 81: Adjust float_in_range" \
  '{"opts":[{"kind":"float","name":"rate","default":0.5}],"adjusts":[{"target":"rate","filter":{"float_in_range":[0.0,1.0]}}],"args":["--rate","0.7"]}' \
  '{"ok":true,"values":{"rate":0.7}}'

# ============================================================
# Test 82: Adjust target not found
# ============================================================
test_parse "Test 82: Adjust target not found" \
  '{"opts":[{"kind":"int","name":"port","default":8080}],"adjusts":[{"target":"nonexistent","filter":{"in_range":[1,65535]}}],"args":[]}' \
  '{"ok":false,"error":"adjust target not found: nonexistent"}'

# ============================================================
# Test 83: Adjust not applied when target unset
# ============================================================
test_parse "Test 83: Adjust unset not applied" \
  '{"opts":[{"kind":"int","name":"port","default":0}],"adjusts":[{"target":"port","filter":{"in_range":[1,65535]}}],"args":[]}' \
  '{"ok":true,"values":{"port":0}}'

# ============================================================
# Test 84: Adjust with to_lower filter
# ============================================================
test_parse "Test 84: Adjust to_lower" \
  '{"opts":[{"kind":"string","name":"mode","default":""}],"adjusts":[{"target":"mode","filter":"to_lower"}],"args":["--mode","DEBUG"]}' \
  '{"ok":true,"values":{"mode":"debug"}}'

# ============================================================
# Test 85: Adjust with to_upper filter
# ============================================================
test_parse "Test 85: Adjust to_upper" \
  '{"opts":[{"kind":"string","name":"mode","default":""}],"adjusts":[{"target":"mode","filter":"to_upper"}],"args":["--mode","debug"]}' \
  '{"ok":true,"values":{"mode":"DEBUG"}}'

# ============================================================
# Test 86: env_prefix basic
# ============================================================
test_parse "Test 86: Env prefix basic" \
  '{"env_prefix":"MYAPP","opts":[{"kind":"int","name":"port","default":8080,"env":"PORT"}],"args":[],"env":{"MYAPP_PORT":"3000"}}' \
  '{"ok":true,"values":{"port":3000}}'

# ============================================================
# Test 87: env_prefix - unprefixed env not matched
# ============================================================
test_parse "Test 87: Env prefix unprefixed not matched" \
  '{"env_prefix":"MYAPP","opts":[{"kind":"string","name":"host","default":"localhost","env":"HOST"}],"args":[],"env":{"HOST":"should-not-apply"}}' \
  '{"ok":true,"values":{"host":"localhost"}}'

# ============================================================
# Test 88: env_prefix - CLI overrides prefixed env
# ============================================================
test_parse "Test 88: Env prefix CLI overrides" \
  '{"env_prefix":"MYAPP","opts":[{"kind":"int","name":"port","default":8080,"env":"PORT"}],"args":["--port","9090"],"env":{"MYAPP_PORT":"3000"}}' \
  '{"ok":true,"values":{"port":9090}}'

# ============================================================
# Test 89: env_prefix - subcmd auto-nesting
# ============================================================
test_parse "Test 89: Env prefix subcmd nesting" \
  '{"env_prefix":"MYAPP","opts":[{"kind":"command","name":"serve","opts":[{"kind":"int","name":"port","default":8080,"env":"PORT"}]}],"args":["serve"],"env":{"MYAPP_SERVE_PORT":"4000"}}' \
  '{"ok":true,"values":{},"command":{"name":"serve","values":{"port":4000}}}'

# ============================================================
# Test 90: No env_prefix behaves as before
# ============================================================
test_parse "Test 90: No env_prefix behaves as before" \
  '{"opts":[{"kind":"string","name":"host","default":"localhost","env":"HOST"}],"args":[],"env":{"HOST":"env-host"}}' \
  '{"ok":true,"values":{"host":"env-host"}}'

# ============================================================
# Test 91: auto_env binds NAME automatically
# ============================================================
test_parse "Test 91: Auto env binds NAME" \
  '{"auto_env":true,"opts":[{"kind":"string","name":"name","default":""}],"args":[],"env":{"NAME":"from-env"}}' \
  '{"ok":true,"values":{"name":"from-env"}}'

# ============================================================
# Test 92: Explicit env takes priority over auto_env
# ============================================================
test_parse "Test 92: Explicit env overrides auto_env" \
  '{"auto_env":true,"opts":[{"kind":"string","name":"host","default":"localhost","env":"MY_HOST"}],"args":[],"env":{"MY_HOST":"explicit-host","HOST":"auto-host"}}' \
  '{"ok":true,"values":{"host":"explicit-host"}}'

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}=== Results ===${NC}"
echo -e "Total:  $TOTAL"
echo -e "${GREEN}Passed: $PASS${NC}"
if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}Failed: $FAIL${NC}"
  echo ""
  echo -e "${RED}Failed tests:${NC}"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
fi
if [[ $SKIP -gt 0 ]]; then
  echo -e "${YELLOW}Skipped: $SKIP${NC}"
fi
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}All tests passed.${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed.${NC}"
  exit 1
fi
