# Sentinel Analytics Rule Drift Report

- Generated: 2026-11-27T15:53:49Z
- Resource Group: prt-uks-siem-rg
- Workspace: PRT-UKS-SIEM-LAW

## Summary

| Bucket | Count |
| --- | ---: |
| Total deployed | 316 |
| Content Hub clean | 236 |
| Content Hub drift | 0 |
| Custom clean | 78 |
| Custom drift | 0 |
| Orphan | 1 |
| Managed (excluded) | 1 |

## Orphan Rules (absorbed into the repo)

These rules were created directly in the Sentinel portal and had no source of truth in the repository. Each has been exported to a Custom rule file under `Content/AnalyticalRules/AbsorbedFromPortal/Orphans/`, so the next deploy governs it.

| Display name | Rule GUID | Kind | Enabled | Absorbed as |
| --- | --- | --- | --- | --- |
| A new Lighthouse service provider was added | 18a8e88e-f1fb-4dc3-9ea7-985637bcaebd | Scheduled | True | `Content/AnalyticalRules/AbsorbedFromPortal/Orphans/A-new-Lighthouse-service-provider-was-added.yaml` (created) |

