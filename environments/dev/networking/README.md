# networking

VNet + one subnet (`platform`, with the `Microsoft.KeyVault` service
endpoint), plus this stack's own Contributor/Reader role assignments for
the three Entra groups `identity` creates.

Depends on `identity` (reads its remote state for the three group object
IDs — `identity` must have a real applied state in the backend before this
stack's `plan`/`apply` can succeed, not just exist in the same PR's diff).
