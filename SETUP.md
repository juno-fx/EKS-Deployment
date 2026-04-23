# Juno EKS Setup Guide

This guide will get Orion up and running in an EKS cluster quickly and easily. If you have any questions you can see more detailed documentation
[here](https://juno-fx.github.io/Orion-Documentation/latest/installation/advanced/eks/pre/). You can also reach out to our [support team](https://www.juno-innovations.com/contact/support)

## Prerequisites

- AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`)
- [eksctl](https://eksctl.io/installation/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- (Optional) [aws-iam-authenticator](https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html) installed

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

**To add Karpenter:**

1. Copy the Karpenter manifests:

```bash
cp examples/karpenter-nodeclass.yaml <name>/
cp examples/karpenter-nodepool-service.yaml <name>/
```

2. Update each manifest with your values:
   - `karpenter-nodeclass.yaml`: Update `role`, `subnetSelectorTerms`, `securityGroupSelectorTerms`
   - NodePool: Update `topology.kubernetes.io/zone`, `instanceTypes`, and `limits` as needed
   - Change `capacity-type` to `["on-demand"]` if you don't want spot instances

3. Apply the manifests:

```bash
kubectl apply -f <name>/karpenter-nodeclass.yaml
kubectl apply -f <name>/karpenter-nodepool-service.yaml
```

4. Verify nodes are being provisioned:

```bash
kubectl get nodes
kubectl get nodepools
```

See `examples/karpenter-nodepool-gpu.yaml` and `examples/karpenter-nodepool-arm64.yaml` for additional pool examples.

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
2. Update the `aws-load-balancer-subnets` annotation with your subnet IDs (comma-separated if multiple)
   - To retrieve your subnet IDs run:
   `eksctl get cluster --name <cluster-name> --region <region> -o json | jq '.[0].ResourcesVpcConfig.SubnetIds'`
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

## Step 5: DNS (~1 min)

Create DNS records pointing to the NLB from ingress-nginx:

| Record                  | Target       |
|-------------------------|--------------|
| `admin.<your-domain>`   | NLB DNS name |
| `project.<your-domain>` | NLB DNS name |

Find the NLB DNS name with:

```bash
kubectl get svc -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Using [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) to automate record creation is recommended.

## Step 6: Install Juno

1. Ensure you are connected to the EKS cluster (see [Reconnecting to an Existing Cluster](#reconnecting-to-an-existing-cluster))
2. Navigate to [juno-innovations.com](https://juno-innovations.com)
3. Click the one-click install button on the homepage
4. Select **Existing Cluster** as the deployment target
5. Follow the prompts to complete the installation

Juno will be installed on your EKS cluster via Helm.

Once installed, access the Juno admin console at `https://admin.<your-domain>` to begin configuration.

## Reconnecting to an Existing Cluster

To reconnect to a previously created cluster for maintenance:

1. Set your AWS credentials:

```bash
export AWS_ACCESS_KEY_ID=<your-access-key-id>
export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
export AWS_SESSION_TOKEN=<your-session-token>
```

2. Verify cluster access:

```bash
export KUBECONFIG=configs/<name>.yaml
kubectl get nodes
```

Replace `<name>` with your cluster name.
