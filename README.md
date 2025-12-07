# platform-devenv

Shared devenv modules for maxdaten.io platform projects.

## Usage

Add to your `devenv.yaml`:

```yaml
inputs:
  nixpkgs:
    url: github:NixOS/nixpkgs/nixpkgs-unstable
  gcloud-auth-plugin:
    url: github:maxdaten-io/gke-gcloud-auth-plugin-nix
  platform-devenv:
    url: github:maxdaten-io/platform-devenv
    flake: false

imports:
  - platform-devenv/modules/google-cloud.nix
  # Or import all modules:
  # - platform-devenv/modules
```

Configure in your `devenv.nix`:

```nix
{ pkgs, ... }:

{
  google-cloud = {
    enable = true;
    projectId = "your-gcp-project-id";
    cluster = {
      name = "your-cluster-name";
      region = "europe-north1";
      getCredentials = true;
    };
  };
}
```

## Modules

### google-cloud

GKE cluster access and GCP tools.

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `google-cloud.enable` | bool | false | Enable the google-cloud module |
| `google-cloud.projectId` | string | "" | GCP project ID |
| `google-cloud.cluster.name` | string | "" | GKE cluster name |
| `google-cloud.cluster.region` | string | "" | GKE cluster region |
| `google-cloud.cluster.getCredentials` | bool | true | Auto-fetch cluster credentials on shell entry |
| `google-cloud.sops.enable` | bool | false | Enable SOPS for secrets management |

**Provided tools:**

- `gcloud` - Google Cloud SDK
- `kubectl` - Kubernetes CLI
- `k9s` - Terminal UI for Kubernetes
- `helm` - Kubernetes package manager
- `flux` - GitOps toolkit
- `kustomize` - Kubernetes manifest customization
- `crossplane-cli` - Crossplane infrastructure orchestration
- `istioctl` - Istio service mesh CLI
- `telepresence2` - Local development with remote cluster

## Requirements

The `gcloud-auth-plugin` input is required for GKE authentication:

```yaml
inputs:
  gcloud-auth-plugin:
    url: github:maxdaten-io/gke-gcloud-auth-plugin-nix
```