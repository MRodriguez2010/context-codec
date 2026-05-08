#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR=$(mktemp -d)
CODEC="bash $SCRIPT_DIR/codec.sh -d $TEST_DIR"
METRICS="bash $SCRIPT_DIR/codec-metrics.sh -d $TEST_DIR"
DIGEST="bash $SCRIPT_DIR/codec-digest.sh -d $TEST_DIR"
PASS=0
FAIL=0
TOTAL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" pattern="$2" text="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$text" | grep -qE "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (pattern '$pattern' not found)"
    echo "    text: $text"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local label="$1" expected_code="$2"
  shift 2
  TOTAL=$((TOTAL + 1))
  set +e
  "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  if [[ $rc -eq $expected_code ]]; then
    echo "  PASS: $label (exit $rc)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected_code, got $rc)"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================="
echo "Context Codec Test Harness"
echo "============================================="
echo "Test dir: $TEST_DIR"
echo ""

echo "[1] Initialization"
$CODEC init --force >/dev/null 2>&1
assert_eq "config.json exists" "true" "$([[ -f $TEST_DIR/config.json ]] && echo true || echo false)"
assert_eq "digest.md exists" "true" "$([[ -f $TEST_DIR/digest.md ]] && echo true || echo false)"
assert_eq "metrics.json exists" "true" "$([[ -f $TEST_DIR/metrics.json ]] && echo true || echo false)"
assert_eq "turns/ dir exists" "true" "$([[ -d $TEST_DIR/turns ]] && echo true || echo false)"

out=$($DIGEST validate -d "$TEST_DIR" 2>&1)
assert_contains "initial digest validates" "valid" "$out"
echo ""

echo "[2] Digest CRUD"
out=$($DIGEST read -d "$TEST_DIR")
assert_contains "initial digest has GOAL" "### GOAL:" "$out"
assert_contains "initial digest has STATE" "### STATE:" "$out"

NEW_DIGEST='## DIGEST v1 | Turn 1 | 2025-04-01T00:00:00Z
### GOAL: Debug failing API tests
### STATE: Identified 4 failing tests out of 45
### CONTEXT: 2 timeouts (auth, rate_limit), 2 assertion failures (user CRUD)
### PENDING: Inspect auth.ts:89 and middleware.ts:45 for timeout causes
### ARTIFACTS: (none)
### TOOL_CACHE: TESTS|suite=api|total=45|pass=41|fail=4'

echo "$NEW_DIGEST" | $DIGEST update -d "$TEST_DIR"
out=$($DIGEST read -d "$TEST_DIR")
assert_contains "updated digest has new GOAL" "Debug failing API tests" "$out"

out=$($DIGEST validate -d "$TEST_DIR" 2>&1)
assert_contains "updated digest validates" "valid" "$out"

out=$($DIGEST tokens -d "$TEST_DIR")
assert_contains "token count is numeric" "^[0-9]+$" "$out"
echo ""

echo "[3] Turn Archiving"
$DIGEST archive-turn -d "$TEST_DIR" >/dev/null 2>&1
assert_eq "T001.md archived (from Turn 1 digest)" "true" "$([[ -f $TEST_DIR/turns/T001.md ]] && echo true || echo false)"

DIGEST_T2='## DIGEST v1 | Turn 2 | 2025-04-01T00:01:00Z
### GOAL: Debug failing API tests
### STATE: Found root cause in auth.ts:89 — timeout due to missing await
### CONTEXT: 2 timeouts (auth, rate_limit), 2 assertion failures; auth.ts:89 missing await
### PENDING: Fix auth.ts, re-run tests
### ARTIFACTS: auth.ts (pending fix)
### TOOL_CACHE: TESTS|suite=api|total=45|pass=41|fail=4'

echo "$DIGEST_T2" | $DIGEST update -d "$TEST_DIR" >/dev/null 2>&1
$DIGEST archive-turn -d "$TEST_DIR" >/dev/null 2>&1
assert_eq "T002.md archived (from Turn 2 digest)" "true" "$([[ -f $TEST_DIR/turns/T002.md ]] && echo true || echo false)"
echo ""

echo "[4] Metrics Recording"
$METRICS record -t 1 -r 3000 -c 80 -d "$TEST_DIR" >/dev/null 2>&1
$METRICS record -t 2 -r 2500 -c 120 -d "$TEST_DIR" >/dev/null 2>&1
$METRICS record -t 3 -r 4000 -c 150 -d "$TEST_DIR" >/dev/null 2>&1

out=$($METRICS ratio -d "$TEST_DIR")
assert_contains "ratio over 3 turns" "3 turns" "$out"
assert_contains "raw total 9500" "9500" "$out"
assert_contains "compressed total 350" "350" "$out"

out=$($METRICS status -d "$TEST_DIR")
assert_contains "status shows turns recorded" "Turns recorded:.*3" "$out"
assert_contains "status shows tokens saved" "Tokens saved:.*9150" "$out"
echo ""

echo "[5] Metrics Export"
out=$($METRICS export -d "$TEST_DIR")
assert_contains "export is JSON with turns array" '"turns"' "$out"
assert_contains "export has 3 turn entries" '"turn":3' "$out"
echo ""

echo "[6] Token Limit Check"
assert_exit "within limit exits 0" 0 bash "$SCRIPT_DIR/codec-digest.sh" check-limit -d "$TEST_DIR"

HUGE_DIGEST='## DIGEST v1 | Turn 99 | 2025-04-01T00:00:00Z
### GOAL: This is an extremely long goal that goes on and on
### STATE: This is an extremely long state description'
for i in $(seq 1 100); do
  HUGE_DIGEST="$HUGE_DIGEST
### CONTEXT: fact_$i — some important context item number $i that takes up space in the digest to push us over the token limit threshold that we configured at init time which was 2000 tokens by default"
done
HUGE_DIGEST="$HUGE_DIGEST
### PENDING: lots of pending items
### ARTIFACTS: many artifacts
### TOOL_CACHE: lots of cached data"

echo "$HUGE_DIGEST" | $DIGEST update -d "$TEST_DIR" >/dev/null 2>&1
assert_exit "over limit exits 1" 1 bash "$SCRIPT_DIR/codec-digest.sh" check-limit -d "$TEST_DIR"
echo ""

echo "[7] Reset"
$CODEC reset >/dev/null 2>&1
out=$($DIGEST read -d "$TEST_DIR")
assert_contains "reset digest has Turn 0" "Turn 0" "$out"

out=$($METRICS ratio -d "$TEST_DIR")
assert_contains "reset metrics show 0 turns" "0 turns" "$out"
echo ""

echo "[8] Multi-turn Compression Simulation"
$CODEC init --force -d "$TEST_DIR" >/dev/null 2>&1

declare -a RAW_SIZES=(3000 2500 4000 1500 5000 2000 3500 1800 4500 2200)
declare -a COMP_SIZES=(80 120 150 60 200 90 140 70 180 100)

DIGESTS=(
'## DIGEST v1 | Turn 1 | 2025-04-01T00:01:00Z
### GOAL: Build REST API for task management
### STATE: Project initialized, Express server scaffolded
### CONTEXT: Using TypeScript, Express, PostgreSQL
### PENDING: Define data models, implement CRUD routes
### ARTIFACTS: package.json, tsconfig.json, src/index.ts
### TOOL_CACHE: NPM_INIT|deps=5|devDeps=8|scripts=4'
'## DIGEST v1 | Turn 2 | 2025-04-01T00:02:00Z
### GOAL: Build REST API for task management
### STATE: Data models defined, Task and User schemas created
### CONTEXT: TypeScript+Express+PostgreSQL; using Prisma ORM
### PENDING: Implement CRUD routes, add auth middleware
### ARTIFACTS: package.json, tsconfig.json, src/index.ts, prisma/schema.prisma
### TOOL_CACHE: PRISMA_MIGRATE|status=ok|tables=2'
'## DIGEST v1 | Turn 3 | 2025-04-01T00:03:00Z
### GOAL: Build REST API for task management
### STATE: CRUD routes implemented for /tasks and /users
### CONTEXT: TypeScript+Express+PostgreSQL+Prisma; REST endpoints live
### PENDING: Add auth, write tests, error handling
### ARTIFACTS: src/{index,routes/{tasks,users},models/{task,user}}.ts, prisma/schema.prisma
### TOOL_CACHE: TESTS|suite=api|total=0|status=not-run'
'## DIGEST v1 | Turn 4 | 2025-04-01T00:04:00Z
### GOAL: Build REST API for task management
### STATE: JWT auth middleware added, protecting /tasks routes
### CONTEXT: TypeScript+Express+PostgreSQL+Prisma; JWT via jsonwebtoken
### PENDING: Write tests, add error handling middleware
### ARTIFACTS: src/{index,routes/*,models/*,middleware/auth}.ts
### TOOL_CACHE: AUTH_TEST|manual=true|status=working'
'## DIGEST v1 | Turn 5 | 2025-04-01T00:05:00Z
### GOAL: Build REST API for task management
### STATE: Tests written for tasks CRUD, 12 passing
### CONTEXT: TypeScript+Express+PostgreSQL+Prisma+JWT; using Jest+supertest
### PENDING: Error handling, validation, rate limiting
### ARTIFACTS: src/{...,__tests__/tasks.test.ts}
### TOOL_CACHE: TESTS|suite=api|total=12|pass=12|fail=0|duration=3.2s'
'## DIGEST v1 | Turn 6 | 2025-04-01T00:06:00Z
### GOAL: Build REST API for task management
### STATE: Error handling middleware + Zod validation added
### CONTEXT: TypeScript+Express+PostgreSQL+Prisma+JWT+Zod; centralized error handling
### PENDING: Rate limiting, pagination, docs
### ARTIFACTS: src/{...,middleware/errorHandler.ts,validators/*.ts}
### TOOL_CACHE: TESTS|suite=api|total=18|pass=18|fail=0'
'## DIGEST v1 | Turn 7 | 2025-04-01T00:07:00Z
### GOAL: Build REST API for task management
### STATE: Rate limiting via express-rate-limit, cursor pagination on /tasks
### CONTEXT: TypeScript+Express+PostgreSQL+Prisma+JWT+Zod; rate-limit=100/15min
### PENDING: API docs, deployment config
### ARTIFACTS: src/{...,middleware/rateLimiter.ts}
### TOOL_CACHE: PERF|avg_latency=45ms|p99=120ms'
'## DIGEST v1 | Turn 8 | 2025-04-01T00:08:00Z
### GOAL: Build REST API for task management
### STATE: Swagger/OpenAPI docs generated, available at /api-docs
### CONTEXT: Full stack: TS+Express+PG+Prisma+JWT+Zod+Swagger
### PENDING: Docker setup, CI pipeline
### ARTIFACTS: src/{...,swagger.ts}, docs/openapi.yaml
### TOOL_CACHE: DOCS|format=openapi3|endpoints=8|schemas=4'
'## DIGEST v1 | Turn 9 | 2025-04-01T00:09:00Z
### GOAL: Build REST API for task management
### STATE: Dockerized with multi-stage build, docker-compose for dev
### CONTEXT: Full stack + Docker; compose has app+db+redis services
### PENDING: CI pipeline, production readiness review
### ARTIFACTS: Dockerfile, docker-compose.yml, .dockerignore, src/*
### TOOL_CACHE: DOCKER_BUILD|size=145MB|layers=12|time=34s'
'## DIGEST v1 | Turn 10 | 2025-04-01T00:10:00Z
### GOAL: Build REST API for task management
### STATE: GitHub Actions CI with lint+test+build+docker-push; project complete
### CONTEXT: Full stack + Docker + CI; all 24 tests green
### PENDING: (none — ready for deployment)
### ARTIFACTS: .github/workflows/ci.yml, Dockerfile, docker-compose.yml, src/*
### TOOL_CACHE: CI|pipeline=github-actions|stages=4|tests=24/24|build=ok'
)

total_raw=0
total_comp=0

for i in $(seq 0 9); do
  turn=$((i + 1))

  $DIGEST archive-turn -d "$TEST_DIR" >/dev/null 2>&1
  echo "${DIGESTS[$i]}" | $DIGEST update -d "$TEST_DIR" >/dev/null 2>&1
  $METRICS record -t "$turn" -r "${RAW_SIZES[$i]}" -c "${COMP_SIZES[$i]}" -d "$TEST_DIR" >/dev/null 2>&1

  total_raw=$((total_raw + RAW_SIZES[i]))
  total_comp=$((total_comp + COMP_SIZES[i]))
done

out=$($METRICS status -d "$TEST_DIR")
assert_contains "10-turn simulation: 10 turns" "Turns recorded:.*10" "$out"
assert_contains "10-turn simulation: raw=30000" "Raw tokens:.*30000" "$out"
assert_contains "10-turn simulation: compressed=1190" "Compressed tokens:.*1190" "$out"
assert_contains "10-turn simulation: saved=28810" "Tokens saved:.*28810" "$out"

ratio_line=$($METRICS ratio -d "$TEST_DIR" | head -1)
assert_contains "10-turn ratio is 25.2:1" "25\.2:1" "$ratio_line"

out=$($DIGEST validate -d "$TEST_DIR" 2>&1)
assert_contains "final digest valid" "valid" "$out"

num_archived=$(find "$TEST_DIR/turns" -maxdepth 1 -name 'T*.md' | wc -l | tr -d ' ')
assert_eq "10 turns archived" "10" "$num_archived"

out=$($DIGEST info -d "$TEST_DIR")
assert_contains "info shows Turn 10" "Turn:.*10" "$out"

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All tests passed."
