# EKS-Deployment

EKS cluster deployment templates for Juno customer environments.

## Overview

This repository provides deployment templates and guides for setting up Amazon EKS clusters with ArgoCD and 
ingress-nginx. Customers can use these templates to deploy a fully functional EKS cluster ready for 
Juno installation.

**What this repo provides:**
- `eksctl` cluster configuration templates with managed node groups
- Karpenter NodePool reference templates (optional, fully customizable)
- ArgoCD Application manifests for GitOps-based workloads
- Step-by-step setup guide from cluster creation to Juno installation

**Architecture:**
- EKS with managed node groups for initial provisioning
- Optional Karpenter support for cost-optimized node provisioning
- ArgoCD for GitOps-based workload deployment
- ingress-nginx with AWS NLB (Network Load Balancer) for ingress
- Private VPC (no NAT gateway) for secure workloads

## Quick Start

See [SETUP.md](./SETUP.md) for step-by-step deployment instructions.

## Repository Structure

```
├── examples/
│   ├── eks.yaml                      # EKS cluster template (eksctl format)
│   ├── nginx.yaml                    # ArgoCD Application for ingress-nginx
│   ├── karpenter-nodeclass.yaml      # Karpenter EC2NodeClass base config
│   ├── karpenter-nodepool-service.yaml  # Service node pool (spot instances)
│   ├── karpenter-nodepool-gpu.yaml   # GPU node pool (on-demand)
│   └── karpenter-nodepool-arm64.yaml # ARM64 node pool (spot instances)
├── devbox.json       # Dev environment configuration
├── AGENTS.md         # Agent instructions
├── SETUP.md          # Deployment guide
└── README.md         # This file
```
