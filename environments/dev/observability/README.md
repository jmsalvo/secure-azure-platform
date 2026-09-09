# observability

A single Log Analytics workspace (30-day retention, `PerGB2018` SKU).

The resource group (`rg-sap-dev-observability`) and every RBAC assignment on
it is created by `bootstrap/` (run as a subscription Owner); this stack
reads the group with `data "azurerm_resource_group" "this"` and creates only
the workspace inside it. See
[ADR 0002](../../../docs/decisions/0002-resource-groups-in-bootstrap.md).

No upstream stack dependency — the only input is `location`. Independent of
`networking` — the two apply in parallel.
