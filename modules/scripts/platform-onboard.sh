#!/usr/bin/env bash

set -euo pipefail

# --- Constants ---
SCHEMA_URL="https://raw.githubusercontent.com/maxdaten-io/gitops/main/foundation/04-platform/functions/webhook-relay/schemas/platform_v1.json"
FALLBACK_API_ALLOWLIST=("sqladmin.googleapis.com" "aiplatform.googleapis.com" "gmail.googleapis.com" "storage.googleapis.com")

# Fetch API allowlist from schema (single source of truth), fall back to hardcoded list
if schema_json=$(curl -sfL --max-time 5 "$SCHEMA_URL" 2>/dev/null); then
  mapfile -t API_ALLOWLIST < <(echo "$schema_json" | jq -r '.properties.apis.items.enum[]')
  if [[ ${#API_ALLOWLIST[@]} -eq 0 ]]; then
    API_ALLOWLIST=("${FALLBACK_API_ALLOWLIST[@]}")
  fi
else
  API_ALLOWLIST=("${FALLBACK_API_ALLOWLIST[@]}")
fi

BUDGET_MIN=1
BUDGET_MAX=20
BUDGET_DEFAULT=3
OUTPUT_FILE="xplatform.yaml"

# --- Defaults ---
OWNERS=()
BUDGET=""
SECRETS=""
APIS=()
MANIFEST_PATH=""
DELETION_POLICY=""
IMAGE_AUTOMATION=""
INTERACTIVE=true

show_help() {
  cat <<'USAGE'
Usage: platform-onboard [FLAGS]

Scaffold an xplatform.yaml for Maxdaten platform onboarding.

Flags:
  --owner EMAIL           Owner email (repeatable)
  --budget N              Monthly budget in USD (1-20, default: 3)
  --secrets               Provision a SecretStore
  --apis API,...          Additional GCP APIs (comma-separated)
  --manifest-path PATH   Manifest path in repo (default: k8s/)
  --deletion-policy P    PREVENT or DELETE (default: PREVENT)
  --image-automation     Enable Flux image automation
  --non-interactive      Skip gum prompts, use flags/defaults
  -h, --help             Show this help

Examples:
  platform-onboard
  platform-onboard --owner me@x.com --budget 5 --non-interactive
USAGE
}

# --- Validation ---
validate_email() {
  if [[ ! "$1" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    echo "Error: '$1' is not a valid email address." >&2
    return 1
  fi
}

validate_budget() {
  if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt "$BUDGET_MIN" ] || [ "$1" -gt "$BUDGET_MAX" ]; then
    echo "Error: Budget must be between 1 and 20." >&2
    return 1
  fi
}

validate_apis() {
  for api in "$@"; do
    local found=false
    for allowed in "${API_ALLOWLIST[@]}"; do
      if [[ "$api" == "$allowed" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" == "false" ]]; then
      echo "Error: API '$api' is not allowed. Allowed: ${API_ALLOWLIST[*]}" >&2
      return 1
    fi
  done
}

validate_manifest_path() {
  if [[ "$1" == *..* ]]; then
    echo "Error: Path traversal (..) is not allowed in manifest path." >&2
    return 1
  fi
}

# --- Flag parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    show_help
    exit 0
    ;;
  --owner)
    OWNERS+=("$2")
    shift 2
    ;;
  --budget)
    BUDGET="$2"
    shift 2
    ;;
  --secrets)
    SECRETS=true
    shift
    ;;
  --apis)
    IFS=',' read -ra APIS <<< "$2"
    shift 2
    ;;
  --manifest-path)
    MANIFEST_PATH="$2"
    shift 2
    ;;
  --deletion-policy)
    DELETION_POLICY="$2"
    shift 2
    ;;
  --image-automation)
    IMAGE_AUTOMATION=true
    shift
    ;;
  --non-interactive)
    INTERACTIVE=false
    shift
    ;;
  *)
    echo "Unknown argument: $1" >&2
    show_help
    exit 1
    ;;
  esac
done

# --- Interactive prompts (gum) ---
if [[ "$INTERACTIVE" == "true" ]]; then
  if [[ ${#OWNERS[@]} -eq 0 ]]; then
    owner_input=$(gum input --placeholder "you@example.com" --header "Owner email (Google account)")
    if [[ -n "$owner_input" ]]; then
      OWNERS+=("$owner_input")
    fi
  fi

  if [[ -z "$BUDGET" ]]; then
    BUDGET=$(gum input --placeholder "3" --header "Monthly budget in USD (1-20)" --value "${BUDGET_DEFAULT}")
  fi

  if [[ -z "$SECRETS" ]]; then
    if gum confirm "Provision a SecretStore?"; then
      SECRETS=true
    else
      SECRETS=false
    fi
  fi

  if [[ ${#APIS[@]} -eq 0 ]]; then
    mapfile -t APIS < <(gum choose --no-limit --header "Additional GCP APIs (space to select)" \
      "${API_ALLOWLIST[@]}" || true)
  fi

  if [[ -z "$MANIFEST_PATH" ]]; then
    MANIFEST_PATH=$(gum input --placeholder "k8s/" --header "Manifest path in repo" --value "k8s/")
  fi

  if [[ -z "$DELETION_POLICY" ]]; then
    DELETION_POLICY=$(gum choose --header "Deletion policy" "PREVENT" "DELETE")
  fi
fi

# --- Apply defaults ---
BUDGET="${BUDGET:-$BUDGET_DEFAULT}"
MANIFEST_PATH="${MANIFEST_PATH:-k8s/}"
SECRETS="${SECRETS:-false}"
DELETION_POLICY="${DELETION_POLICY:-PREVENT}"
IMAGE_AUTOMATION="${IMAGE_AUTOMATION:-false}"

# --- Validate all values ---
if [[ ${#OWNERS[@]} -eq 0 ]]; then
  echo "Error: At least one --owner is required." >&2
  exit 1
fi

for owner in "${OWNERS[@]}"; do
  validate_email "$owner"
done

validate_budget "$BUDGET"

# Filter empty elements from APIS (gum/mapfile may produce empty strings)
_clean_apis=()
for _a in "${APIS[@]+"${APIS[@]}"}"; do [[ -n "$_a" ]] && _clean_apis+=("$_a"); done
APIS=("${_clean_apis[@]+"${_clean_apis[@]}"}")

if [[ ${#APIS[@]} -gt 0 ]]; then
  validate_apis "${APIS[@]}"
fi

validate_manifest_path "$MANIFEST_PATH"

# --- Overwrite check ---
if [[ -f "$OUTPUT_FILE" && "$INTERACTIVE" == "true" ]]; then
  if ! gum confirm "xplatform.yaml already exists. Overwrite?"; then
    exit 0
  fi
fi

# --- Generate YAML ---
{
  cat <<'HEADER'
# Maxdaten Platform configuration
# Docs: https://github.com/maxdaten-io/gitops/blob/main/docs/design/0019-github-app-self-service-onboarding.md
#
# This file declares how your repository is provisioned on the Maxdaten
# platform.  Edit the values below, then push to trigger provisioning.
apiVersion: platform.maxdaten.io/v1
kind: PlatformApp

# Google account emails that receive GCP Editor access and K8s namespace admin.
HEADER

  echo "owners:"
  for o in "${OWNERS[@]}"; do
    echo "  - $o"
  done

  echo ""
  echo "# Monthly budget limit in USD (min: \$1, max: \$20)."
  echo "budget: $BUDGET"

  echo ""
  if [[ "$MANIFEST_PATH" == "k8s/" ]]; then
    echo "# Path inside the repo where Kubernetes manifests are stored."
    echo "# manifestPath: k8s/"
  else
    echo "# Path inside the repo where Kubernetes manifests are stored."
    echo "manifestPath: $MANIFEST_PATH"
  fi

  echo ""
  if [[ ${#APIS[@]} -eq 0 ]]; then
    echo "# Additional GCP APIs to enable in the provisioned project."
    echo "# Allowed: ${API_ALLOWLIST[*]}"
    echo "# apis: []"
  else
    echo "# Additional GCP APIs to enable in the provisioned project."
    echo "apis:"
    for api in "${APIS[@]}"; do
      echo "  - $api"
    done
  fi

  echo ""
  if [[ "$SECRETS" == "false" ]]; then
    echo "# Whether to provision a namespace-scoped SecretStore."
    echo "# secrets: false"
  else
    echo "# Whether to provision a namespace-scoped SecretStore."
    echo "secrets: true"
  fi

  echo ""
  if [[ "$DELETION_POLICY" == "PREVENT" ]]; then
    echo "# What happens when this file is removed. PREVENT (default) blocks deletion."
    echo "# deletionPolicy: PREVENT"
  else
    echo "# What happens when this file is removed. PREVENT (default) blocks deletion."
    echo "deletionPolicy: $DELETION_POLICY"
  fi

  echo ""
  if [[ "$IMAGE_AUTOMATION" == "false" ]]; then
    echo "# Whether Flux image-automation controllers are enabled."
    echo "# imageAutomation: false"
  else
    echo "# Whether Flux image-automation controllers are enabled."
    echo "imageAutomation: true"
  fi
} > "$OUTPUT_FILE"

echo "Created xplatform.yaml"
echo "Next: push to your default branch to trigger onboarding"
