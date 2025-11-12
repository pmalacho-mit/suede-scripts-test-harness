#!/usr/bin/env bash
#
# Test suite for degit.sh utility
# This script tests various scenarios including success cases,
# error handling, and edge cases.
#

set -euo pipefail

readonly EXTERNAL_SCRIPT_DEGIT="https://raw.githubusercontent.com/pmalacho-mit/suede/refs/heads/main/scripts/utils/degit.sh"
readonly OWNER="pmalacho-mit"
readonly REPO="suede-scripts-test-harness"
readonly COMMIT="98f6ba04cccd6d2f555bb5c5d11860d8b770b570"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

source "$ROOT/harness/mock-curl.sh"
source "$ROOT/harness/color-logging.sh"

readonly LOCAL_SCRIPT_DEGIT="$ROOT/suede/scripts/utils/degit.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_DIR=""

setup_test_env() {
  TEST_DIR="$(mktemp -d)"
  log_info "Created test directory: $TEST_DIR"
  
  mock_curl_url "$EXTERNAL_SCRIPT_DEGIT" "$LOCAL_SCRIPT_DEGIT"
  enable_url_mocking
  log_success "Test environment set up"
}

cleanup_test_env() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
    log_info "Cleaned up test directory"
  fi
  disable_url_mocking
}

assert_success() {
  local test_name="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  
  log_info "Running: $test_name"
  
  if "$@"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$test_name"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_error "$test_name"
    return 1
  fi
}

assert_failure() {
  local test_name="$1"
  local expected_exit_code="$2"
  shift 2
  TESTS_RUN=$((TESTS_RUN + 1))
  
  log_info "Running: $test_name"
  
  local actual_exit_code=0
  "$@" || actual_exit_code=$?
  
  if [[ $actual_exit_code -eq $expected_exit_code ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$test_name (exit code: $actual_exit_code)"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_error "$test_name (expected exit code: $expected_exit_code, got: $actual_exit_code)"
    return 1
  fi
}

assert_dir_not_empty() {
  local dir="$1"
  if [[ -d "$dir" && -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
    return 0
  else
    return 1
  fi
}

assert_dir_empty() {
  local dir="$1"
  if [[ -d "$dir" && -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
  echo "========================================"
}

# ============================================================================
# Main
# ============================================================================

main() {
  trap cleanup_test_env EXIT
  setup_test_env
  run_all_tests
  bash <(curl -fsSL https://raw.githubusercontent.com/pmalacho-mit/suede/refs/heads/main/scripts/utils/degit.sh) 
  
  exit $?
}

main "$@"

