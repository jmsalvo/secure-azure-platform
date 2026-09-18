# aks

The `v0.2` hardened AKS cluster: public API server firewalled to an
authorized-IP allow list, split system/user node pools, and a minimal
sample workload proving the hardening is real.

The resource group (`rg-sap-dev-aks`) and every RBAC assignment on it is
created by `bootstrap/` (run as a subscription Owner); this stack reads the
group with `data "azurerm_resource_group" "this"` and creates only the
cluster inside it. See
[ADR 0002](../../../docs/decisions/0002-resource-groups-in-bootstrap.md).

Depends on `networking` (the `aks` subnet) and `observability` (the Log
Analytics workspace for Container Insights). Does not depend on `key-vault`
— nothing here needs Key Vault-backed secrets yet (that's `v0.6`'s job).

## Before you apply

`operator_public_ip_cidr` changes across sessions/networks — re-check it's
still your current IP before every `apply`, or the API server will refuse
you along with everyone else.

## CI configuration

`plan-aks`/`apply_aks`/the `destroy` workflow all need two repo variables
(Settings → Secrets and variables → Actions → Variables) that local runs
instead set in `terraform.tfvars`:

- `OPERATOR_PUBLIC_IP_CIDR` — same value as `operator_public_ip_cidr` above.
- `ADMIN_GROUP_OBJECT_IDS` — JSON-encoded list, e.g.
  `["00000000-0000-0000-0000-000000000000"]` (sap-dev-humans' object ID).

Set them with:
```bash
gh variable set OPERATOR_PUBLIC_IP_CIDR --body "<your-ip>/32"
gh variable set ADMIN_GROUP_OBJECT_IDS --body '["<sap-dev-humans-object-id>"]'
```

Unlike the three Entra group object IDs `bootstrap/` reads from
`terraform.tfvars` (see [ADR 0002](../../../docs/decisions/0002-resource-groups-in-bootstrap.md)),
`admin_group_object_ids` here is not an ARM role assignment — it's a plain
AKS resource property read by CI's resource-group-scoped `Contributor`
role, so no bootstrap change is needed.

## After you apply: deploying the sample workload

The cluster has `local_account_disabled = true` and Azure RBAC for
Kubernetes enabled — there's no local admin kubeconfig fallback, and CI
doesn't have Kubernetes-level RBAC to run `kubectl` unattended (see the
`v0.2` design spec's "Sample workload" section for why that's a deliberate
choice, not an oversight). Deploy it yourself, using your own Entra
identity (already an AKS admin via `admin_group_object_ids`):

```bash
az aks get-credentials --resource-group rg-sap-dev-aks --name <cluster_name output> --overwrite-existing
kubectl apply -f k8s/
```

Reach it via port-forward (the `Service` is `ClusterIP`, no public
`LoadBalancer` — see the design spec's cost reasoning):

```bash
kubectl port-forward svc/sample-workload 8080:80
```

then browse `http://localhost:8080`. Note: `port-forward` tunnels through
the API server directly to the pod, bypassing the `Service`'s normal
network path — so it still works even though the `NetworkPolicy` in `k8s/`
denies ingress from anything except pods labeled
`network-policy-demo-client: "true"`. That's expected: the policy
demonstrates pod-to-pod isolation, not operator access.

## Teardown

`terraform destroy` on this stack deletes the cluster (and everything
running on it, including the sample workload) in one step — no separate
`kubectl delete` needed first.
