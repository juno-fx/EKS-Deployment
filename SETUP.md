# Juno EKS Setup Guide

This guide will get Orion up and running in an EKS cluster quickly and easily. If you have any questions you can see more detailed documentation
[here](https://juno-fx.github.io/Orion-Documentation/latest/installation/advanced/eks/pre/). You can also reach out to our [support team](https://www.juno-innovations.com/contact/support)

## Prerequisites

1. Set your AWS credentials:

```bash
export AWS_ACCESS_KEY_ID=<your-access-key-id>
export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
export AWS_SESSION_TOKEN=<your-session-token> If you have one
```
2. Install tools
 
- [eksctl](https://eksctl.io/installation/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Step 1: Create EKS Cluster (~15 min)

1. Copy `examples/eks.yaml` to `<name>/eks.yaml`
2. Update the following in your copy:
   - `metadata.name` — your cluster name
   - `metadata.region` — your AWS region
   - `metadata.tags.karpenter.sh/discovery` — your cluster name
   - `availabilityZones` — your 2 AZs
   - `managedNodeGroups[].availabilityZones` — your primary AZ
   - `managedNodeGroups[].instanceTypes` - This list may need updating depending on your chosen region, see [this list](https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-regions.html) for full details
3. Create the cluster:

```bash
eksctl create cluster -f <name>/eks.yaml
```

4. Get kubeconfig and verify access:

```bash
mkdir -p configs
eksctl utils write-kubeconfig --cluster <name> --kubeconfig configs/<name>.yaml
export KUBECONFIG=configs/<name>.yaml
kubectl get nodes
```

(Optional) You may need to specify your AWS region if you are unable to see your cluster via `eksctl`

```bash
export AWS_REGION=<your region>
```

You should see your node group nodes listed.

For additional information you can refer to the [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html) directly.

## Step 2: Configure Karpenter NodePools (Optional)

The initial cluster uses managed node groups. Karpenter can be added for cost-optimized node provisioning, but is not required.

The `examples/karpenter-*.yaml` files are reference templates showing one way to configure NodePools. You can:

- Use any instance types you prefer (c5, c6a, m6g, g4dn, etc.)
- Use spot instances, on-demand, or both
- Create any number of NodePools with custom configurations
- Skip Karpenter entirely and use the managed node groups

**NodePool templates available:**

| File | Purpose | Required? |
|------|---------|-----------|
| `karpenter-nodeclass.yaml` | EC2NodeClass — shared by every NodePool below | Always, if using Karpenter |
| `karpenter-nodepool-service.yaml` | Dedicated nodes for ingress-nginx (carries the load-bearing `juno-innovations.com/service: "true"` label) | Always, if using Karpenter |
| `karpenter-nodepool-cpu.yaml` | General-purpose CPU workloads (amd64) | Only if you run CPU workstation workloads |
| `karpenter-nodepool-gpu.yaml` | GPU workloads (amd64, g/p instance families) | Only if you run GPU workstation workloads |
| `karpenter-nodepool-arm64.yaml` | ARM64 workloads | Only if you run ARM workstation workloads |

**Only create the NodePools you actually need.** `service` is the only one tied to a specific platform requirement (the ingress-nginx node-targeting label) and should always be created. `cpu`, `gpu`, and `arm64` are independent — if you have no GPU workload, skip `karpenter-nodepool-gpu.yaml` entirely rather than applying it unused.

**Weight and scheduling priority:**

`cpu` and `gpu` both label nodes `juno-innovations.com/workstation: "true"` and can both satisfy a workstation pod that doesn't pin itself to a specific instance family. `spec.weight` (1-100, default 0) breaks the tie — Karpenter prefers the higher-weight NodePool when more than one could provision for a pod. The templates ship with `cpu: weight 10` > `gpu: weight 5`, so CPU is preferred by default.

- If GPU instances should be preferred instead, raise `gpu`'s weight above `cpu`'s (e.g. `gpu: 10`, `cpu: 5`).
- If you only create one of the two (e.g. GPU-only), weight is moot — there's nothing to compete with.
- `service` and `arm64` don't need a weight: `service` only matches pods that explicitly request its label, and `arm64`'s `kubernetes.io/arch: arm64` requirement keeps it from overlapping with the amd64 `cpu`/`gpu` pools.

**To add Karpenter:**

1. Copy the manifests you need (always copy `karpenter-nodeclass.yaml` and `karpenter-nodepool-service.yaml`; add `cpu`/`gpu`/`arm64` as needed):

```bash
cp examples/karpenter-nodeclass.yaml <name>/
cp examples/karpenter-nodepool-service.yaml <name>/
cp examples/karpenter-nodepool-cpu.yaml <name>/    # only if you need CPU workstation nodes
cp examples/karpenter-nodepool-gpu.yaml <name>/    # only if you need GPU workstation nodes
cp examples/karpenter-nodepool-arm64.yaml <name>/  # only if you need ARM64 workstation nodes
```

2. Update each manifest with your values:
   - `karpenter-nodeclass.yaml`: Update `role`, `subnetSelectorTerms`, `securityGroupSelectorTerms`
   - Each `karpenter-nodepool-*.yaml`: Update `topology.kubernetes.io/zone`, `instanceTypes`, and `limits` as needed — must match the AZ used in `karpenter-nodeclass.yaml`/`eks.yaml`
   - Change `capacity-type` to `["on-demand"]` in any pool where you don't want spot instances
   - If creating both `cpu` and `gpu`, set `weight` on each to reflect which should be preferred (see above)

3. Apply the manifests you copied, e.g.:

```bash
kubectl apply -f <name>/karpenter-nodeclass.yaml
kubectl apply -f <name>/karpenter-nodepool-service.yaml
kubectl apply -f <name>/karpenter-nodepool-cpu.yaml    # if created
kubectl apply -f <name>/karpenter-nodepool-gpu.yaml    # if created
kubectl apply -f <name>/karpenter-nodepool-arm64.yaml  # if created
```

4. Verify nodes are being provisioned:

```bash
# Confirm resources were accepted
kubectl get ec2nodeclass
kubectl get nodepools
kubectl describe nodepool service
kubectl describe ec2nodeclass service

# Check Karpenter controller is healthy
kubectl get pods -n karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50

# Check NodePool status conditions
kubectl get nodepool service -o jsonpath='{.status.conditions}' | jq .
```

## Step 3: Install ArgoCD (~1 min)

```bash
kubectl create namespace argocd
kubectl create -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/refs/heads/master/manifests/install.yaml
```

Wait for ArgoCD to be ready:

```bash
kubectl rollout status deployment/argocd-server -n argocd
```

## Step 4: Deploy ingress-nginx (~3 min)

1. Copy `examples/nginx.yaml` to `<name>/nginx.yaml`
2. Update the `aws-load-balancer-subnets` annotation with your public subnet IDs (comma-separated if multiple)
   - **Step 1** — Get your VPC ID:
   ```bash
   eksctl get cluster --name <cluster-name> --region <region> -o json | jq -r '.[0].ResourcesVpcConfig.VpcId'
   ```
   - **Step 2** — List public subnets eligible for NLB:
   ```bash
   aws ec2 describe-subnets \
     --filters \
       "Name=vpc-id,Values=<vpc-id>" \
       "Name=tag:kubernetes.io/role/elb,Values=1" \
     --query 'Subnets[].[SubnetId,AvailabilityZone]' \
     --output table \
     --region <region>
   ```
   > Use the subnet from your main AZ. .
3. Apply the application:

```bash
kubectl apply -n argocd -f <name>/nginx.yaml
```

4. Verify the ingress-nginx controller is running:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

Wait for the NLB to be provisioned (check the EXTERNAL-IP field).

## Step 5: DNS & TLS

### DNS

Create DNS records (Type A) pointing to the NLB from ingress-nginx:

| Record                  | Target       |
|-------------------------|--------------|
| `admin.<your-domain>`   | NLB DNS name |
| `project.<your-domain>` | NLB DNS name |

Find the NLB DNS name with (Its the external IP):

```bash
kubectl get svc -n ingress-nginx
```

### TLS Certificate

The Ingress resource requires a TLS secret named `ingress-certificate` in the `argocd` namespace.
Choose the path that fits your use case:

---

#### POC / Quick Start — certbot (manual)

**1. Install certbot locally:**

```bash
sudo apt install certbot   # Ubuntu/Debian
brew install certbot       # Mac
```

**2. Generate a cert via DNS challenge (no server required):**

```bash
certbot certonly --manual --preferred-challenges dns \
  -d <your-domain>
```

Certbot will prompt you to add a DNS TXT record to prove domain ownership. Add it in Route 53,
wait ~30 seconds, then press Enter to continue. Certbot will write the cert files to
`/etc/letsencrypt/live/<your-domain>/`.

**3. Copy certs to a readable location (certbot writes as root):**

```bash
sudo cp /etc/letsencrypt/live/<your-domain>/fullchain.pem ~/fullchain.pem
sudo cp /etc/letsencrypt/live/<your-domain>/privkey.pem ~/privkey.pem
sudo chown $USER ~/fullchain.pem ~/privkey.pem
```

**4. Create the TLS secret in the cluster:**

```bash
kubectl create secret tls ingress-certificate \
  --cert=<path-to-file>/fullchain.pem \
  --key=<path-to-file>/privkey.pem \
  -n argocd
```

**5. Verify:**

```bash
kubectl get secret ingress-certificate -n argocd
```

> **Note:** Let's Encrypt certs expire every **90 days**. You must repeat steps 2–4 to renew.
> If kubectl cannot reach the cluster from your laptop (private VPC), use AWS CloudShell in
> the same region and upload the cert files via Actions → Upload file before running step 4.

---

#### Production — cert-manager + ExternalDNS (recommended)

For production deployments, automate both DNS and TLS management:

- **[cert-manager](https://cert-manager.io)** — automatically issues and renews TLS certs via
  Let's Encrypt using a Route 53 DNS-01 `ClusterIssuer`. No manual cert handling required.
- **[ExternalDNS](https://github.com/kubernetes-sigs/external-dns)** — automatically creates
  and updates Route 53 records from Ingress and Service resources. No manual DNS management required.

## Step 6: Install Juno

1. Ensure you are connected to the EKS cluster (see [Reconnecting to an Existing Cluster](#reconnecting-to-an-existing-cluster))
2. Navigate to [juno-innovations.com](https://juno-innovations.com)
3. Click the one-click install button on the homepage
4. Select **Existing Cluster** as the deployment target
5. Enter y if you purchased your license through the AWS marketplace.
6. Follow the prompts to complete the installation

Juno will be installed on your EKS cluster via Helm.

Once installed, access the Juno admin console at `https://admin.<your-domain>` to begin configuration.

[Here](https://juno-fx.github.io/Orion-Documentation/latest/installation/install/license/)
 are the docs to manage your license inside Genesis.


## Reconnecting to an Existing Cluster

To reconnect to a previously created cluster for maintenance:

1. Set your AWS credentials:

```bash
export AWS_ACCESS_KEY_ID=<your-access-key-id>
export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
export AWS_SESSION_TOKEN=<your-session-token> If you have one
```

2. Verify cluster access:

```bash
export KUBECONFIG=configs/<name>.yaml
kubectl get nodes
```

Replace `<name>` with your cluster name.
