#!/usr/bin/env bash
# Validate a Database XR against the platform composition using crossplane render
# Fetches Composition, Functions, and EnvironmentConfigs from the cluster.
#
# Usage: validate-database <database-yaml>
#
# Examples:
#   # Validate a local file
#   validate-database k8s/app/mealie/database.yaml
#
#   # Validate from cluster (bash)
#   validate-database <(kubectl get database.platform.maxdaten.io mealie -n 0-gh-mealieservice-ffed -o yaml)
#
#   # Validate from cluster (fish)
#   validate-database (kubectl get database.platform.maxdaten.io mealie -n 0-gh-mealieservice-ffed -o yaml | psub)
#
# Note: Local files must include namespace and labels that are normally applied by Flux.
#       Cluster resources already have these applied.

set -euo pipefail

# Temporary directory for fetched resources
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

usage() {
    echo "Usage: $0 <database-yaml>"
    echo ""
    echo "Validate a Database XR against the platform composition."
    echo "Fetches Composition, Functions, and EnvironmentConfigs from the cluster."
    echo ""
    echo "Arguments:"
    echo "  database-yaml  Path to Database resource YAML file (or process substitution)"
    echo ""
    echo "Examples:"
    echo "  # Validate a local file"
    echo "  $0 k8s/app/database.yaml"
    echo ""
    echo "  # Validate from cluster (bash)"
    echo "  $0 <(kubectl get database.platform.maxdaten.io mealie -n NAMESPACE -o yaml)"
    echo ""
    echo "  # Validate from cluster (fish)"
    echo "  $0 (kubectl get database.platform.maxdaten.io mealie -n NAMESPACE -o yaml | psub)"
    echo ""
    echo "Note: Local files must include namespace and labels normally applied by Flux."
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

DATABASE_YAML="$1"

if [[ ! -f "${DATABASE_YAML}" ]]; then
    echo "Error: Database YAML file not found: ${DATABASE_YAML}" >&2
    exit 1
fi

echo "Fetching resources from cluster..."

# Fetch the Database composition
echo "  → Fetching Database composition..."
kubectl get composition database-platform-postgres -o yaml > "${TEMP_DIR}/composition.yaml" 2>/dev/null || {
    echo "Error: Could not fetch 'database' Composition from cluster" >&2
    echo "Make sure the Database composition is deployed and you have cluster access" >&2
    exit 1
}

# Fetch all functions referenced by the composition
echo "  → Fetching Functions..."
FUNCTIONS_FILE="${TEMP_DIR}/functions.yaml"
> "${FUNCTIONS_FILE}"  # Create empty file

# Extract function names from composition and fetch each
yq eval '.spec.pipeline[].functionRef.name' "${TEMP_DIR}/composition.yaml" | while read -r func_name; do
    if [[ -n "${func_name}" && "${func_name}" != "null" ]]; then
        echo "    - ${func_name}"
        kubectl get function "${func_name}" -o yaml >> "${FUNCTIONS_FILE}"
        echo "---" >> "${FUNCTIONS_FILE}"
    fi
done

# Fetch all EnvironmentConfigs
echo "  → Fetching EnvironmentConfigs..."
ENVS_DIR="${TEMP_DIR}/envs"
mkdir -p "${ENVS_DIR}"
kubectl get environmentconfigs.apiextensions.crossplane.io -o yaml | \
    yq eval '.items[] | splitDoc' - \
    > "${ENVS_DIR}/environment-configs.yaml"

echo ""
echo "EnvironmentConfigs fetched:"
yq eval-all '.metadata.name' "${ENVS_DIR}/environment-configs.yaml" 2>/dev/null | grep -v '^---$' | sed 's/^/  - /' || echo "  (none)"

echo ""
echo "Running crossplane render..."
echo "  Database:    ${DATABASE_YAML}"
echo "  Composition: (from cluster)"
echo "  Functions:   (from cluster)"
echo ""

crossplane render --verbose \
    "${DATABASE_YAML}" \
    "${TEMP_DIR}/composition.yaml" \
    "${FUNCTIONS_FILE}" \
    --required-resources "${ENVS_DIR}" | yq
