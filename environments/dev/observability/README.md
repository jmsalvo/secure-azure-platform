# observability

A single Log Analytics workspace (30-day retention, `PerGB2018` SKU), plus
this stack's own Contributor/Reader role assignments for the three Entra
groups `identity` creates.

Depends on `identity`, same reason and same constraint as `networking`
(see that stack's README). Independent of `networking` — the two apply in
parallel.
