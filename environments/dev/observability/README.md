# observability

A single Log Analytics workspace (30-day retention, `PerGB2018` SKU), plus
this stack's own Contributor/Reader role assignments for the three
admin-managed Entra groups (`sap-dev-humans`, `sap-dev-ci-plan`,
`sap-dev-ci-apply`).

No upstream stack dependency — the three group object IDs arrive as input
variables fed by GitHub repository variables (see `networking`'s README).
Independent of `networking` — the two apply in parallel.
