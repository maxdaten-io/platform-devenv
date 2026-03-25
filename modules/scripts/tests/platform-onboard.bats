#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../platform-onboard.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
  # Stub gum so it is never actually called in non-interactive mode
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/gum" <<'STUB'
#!/usr/bin/env bash
echo "ERROR: gum should not be called in non-interactive mode" >&2
exit 99
STUB
  chmod +x "$TEST_DIR/bin/gum"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "--help prints usage with --owner, --budget, --apis" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--owner"* ]]
  [[ "$output" == *"--budget"* ]]
  [[ "$output" == *"--apis"* ]]
}

@test "--owner and --budget in non-interactive mode generates xplatform.yaml" {
  run bash "$SCRIPT" --owner user@example.com --budget 5 --non-interactive
  [ "$status" -eq 0 ]
  [ -f xplatform.yaml ]
  run cat xplatform.yaml
  [[ "$output" == *"owners:"* ]]
  [[ "$output" == *"- user@example.com"* ]]
  [[ "$output" == *"budget: 5"* ]]
}

@test "--budget 0 exits non-zero with range error" {
  run bash "$SCRIPT" --budget 0 --owner a@b.com --non-interactive
  [ "$status" -ne 0 ]
  [[ "$output" == *"between 1 and 20"* ]]
}

@test "--budget 25 exits non-zero with range error" {
  run bash "$SCRIPT" --budget 25 --owner a@b.com --non-interactive
  [ "$status" -ne 0 ]
  [[ "$output" == *"between 1 and 20"* ]]
}

@test "invalid email exits non-zero" {
  run bash "$SCRIPT" --owner notanemail --non-interactive
  [ "$status" -ne 0 ]
  [[ "$output" == *"valid email"* ]]
}

@test "disallowed API exits non-zero" {
  run bash "$SCRIPT" --apis "compute.googleapis.com" --owner x@y.com --non-interactive
  [ "$status" -ne 0 ]
  [[ "$output" == *"not allowed"* ]] || [[ "$output" == *"allowlist"* ]]
}

@test "allowed API succeeds" {
  run bash "$SCRIPT" --apis "sqladmin.googleapis.com" --owner x@y.com --non-interactive
  [ "$status" -eq 0 ]
  [ -f xplatform.yaml ]
}

@test "generated file contains apiVersion and kind" {
  run bash "$SCRIPT" --owner test@example.com --non-interactive
  [ "$status" -eq 0 ]
  run cat xplatform.yaml
  [[ "$output" == *"apiVersion: platform.maxdaten.io/v1"* ]]
  [[ "$output" == *"kind: PlatformApp"* ]]
}

@test "generated file contains header comment" {
  run bash "$SCRIPT" --owner test@example.com --non-interactive
  [ "$status" -eq 0 ]
  run cat xplatform.yaml
  [[ "$output" == *"# Maxdaten Platform configuration"* ]]
}

@test "default budget is 3 when not specified" {
  run bash "$SCRIPT" --owner test@example.com --non-interactive
  [ "$status" -eq 0 ]
  run cat xplatform.yaml
  [[ "$output" == *"budget: 3"* ]]
}

@test "path traversal in manifest-path is rejected" {
  run bash "$SCRIPT" --manifest-path "../escape" --owner a@b.com --non-interactive
  [ "$status" -ne 0 ]
  [[ "$output" == *"path traversal"* ]] || [[ "$output" == *".."* ]]
}
