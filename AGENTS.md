# AGENTS.md

## Repo Purpose

EKS cluster deployment templates for Juno customer environments. Provides eksctl configs, ArgoCD app manifests, and setup guides.

## Key Files

- `examples/eks.yaml` — EKS cluster config (eksctl format, managed node groups for initial boot)
- `examples/karpenter-nodeclass.yaml` — Karpenter EC2NodeClass base config
- `examples/karpenter-nodepool-*.yaml` — Karpenter NodePools (service, gpu, arm64)
- `examples/nginx.yaml` — ArgoCD Application for ingress-nginx (GitOps pattern)
- `SETUP.md` — Step-by-step deployment guide for customers
- `devbox.json` — Dev environment (eksctl, aws-iam-authenticator)

## Architecture

- EKS with Karpenter for node provisioning
- Private VPC (nat: Disable) — no internet egress
- Spot instances for cost optimization
- ArgoCD for GitOps-based workload management
- ingress-nginx with AWS NLB (proxy protocol v2)

## Dev Environment

```bash
devbox shell  # loads eksctl, aws-iam-authenticator
```

## Adding ArgoCD Apps

Create new `Application` manifests following `examples/nginx.yaml`:
- Set `metadata.namespace: argocd`
- `spec.syncPolicy.automated` enables auto-sync (prune, selfHeal, allowEmpty)
- `sources[].helm` defines the chart and values
- `aws-load-balancer-subnets` annotation requires customer subnet IDs

## Testing

No tests. `devbox.json` `test` script exits 1 by design.
