# Community Rules: David Alonso - Threat Hunting

## Attribution

These analytical rules were authored by **David Alonso** and sourced from the
[Dalonso Security Repository](https://github.com/davidalonsod/Dalonso-Security-Repo).
David maintains a comprehensive collection of Microsoft Sentinel threat-hunting
detections across identity, endpoint, cloud, and network data sources.

## License

All rules in this directory are released under **The Unlicense** (public domain).
You are free to use, modify, and distribute them without restriction.
See [The Unlicense](https://unlicense.org) for full terms.

## Deployment Note

These rules deploy as **disabled** by default. Enable individual rules in the
Microsoft Sentinel portal after reviewing them against your environment's data
sources, retention, and noise tolerance.

## Categories

| Category | Rule Count |
|---|---|
| AzureActivity | 12 |
| CommonSecurityLog | 37 |
| DNSEvents | 17 |
| NonInteractiveSigninLogs | 23 |
| SigninLogs | 22 |

## AzureActivity

| Name | Severity | Description |
|---|---|---|
| Azure - Automation Runbook Created or Published by First-Time Caller | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure Cryptojacking - High-Compute VM Deployed by New Identity | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Diagnostic Settings Permanently Deleted Without Recreation | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Mass Deletion of Critical Resources (NSGs/VMs/Storage/VNETs/Key Vaults) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Mass Privileged Role Assignments by Single Identity | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Mass Resource Creation Burst by New Identity (Cryptojacking / Persistence) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Privileged Management Operations from a New Source IP for Established Identity | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Resource Lock or Policy Assignment Deleted | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Service Principal CA Bypass Sign-in Followed by Management Operations | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Service Principal Credential Added Then Privileged Role Assigned (Same Initiator, 60 min) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Storage Account SAS Token Bulk Generation | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Azure - Threat Intelligence Match on Management Plane Caller IP (STIX) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |

## CommonSecurityLog

| Name | Severity | Description |
|---|---|---|
| Firewall Beaconing Detection - Regular Outbound Connections | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Firewall Anomalous Outbound Data Volume - Exfiltration Risk | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Firewall Traffic to Threat Intelligence Flagged IP | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Firewall Port Scan Detection - Vertical and Horizontal Sweeps | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Firewall Allowed Traffic to High-Risk Country | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Lateral Movement - Internal Host Port Sweep on Admin/Pivot Ports | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Fortinet IPS - High-Frequency Intrusion Prevention Alerts | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Palo Alto Networks - Threat Log Events (Spyware, Wildfire, Vulnerability) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Blocked Request to Malicious / C2 Category | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Shadow IT and Unauthorized File Sharing - High Volume | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNS Tunneling Indicators - Anomalously Long Hostnames | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Firewall New First-Seen External IP Contacted | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Correlation: Firewall Allowed Traffic + Azure AD Sign-In from Same IP | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Correlation: Firewall Traffic + Active Security Alert - Shared IOC IP | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Correlation: Firewall Traffic Matching Threat Intelligence Domain / URL | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Palo Alto Networks - High-Volume Inter-Zone Policy Denies | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Fortinet SSL-VPN and Admin Authentication Brute Force | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Impossible Travel (Same User, Multiple Locations in 1 Hour) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Protocol Anomaly - HTTP or HTTPS on Non-Standard Ports | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Correlation: Firewall Traffic from High-Risk Identity (IdentityInfo) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - DLP Policy Violation - Blocked Sensitive Data Upload | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Advanced Threat Protection (ATP) / Sandbox Malicious File Blocked | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Mass Cloud Storage Download - Data Staging Risk | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Uncategorized or Newly Registered Domain Request Spike | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Tunnel, SOCKS Proxy, or SSL Bypass Category Detected | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Off-Hours High-Volume Proxy Activity (Behavioral Anomaly) | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Multi-User Phishing Campaign - Same Domain Hit by 3+ Users in 1 Hour | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - High ThreatRiskLevel Browsing in Allowed Traffic | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Sudden Category Shift - User Accessing New High-Risk URL Categories | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA / ZPA - Visibility Loss - No Events Received in 2 Hours | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZPA - Access to Internal Application from Anomalous Geolocation | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZPA - Repeated Connection Failures - Possible Credential Spray Against Internal Apps | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZPA - First-Time Access to Internal Application - Possible Lateral Movement | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZPA - App Access Volume Spike - User Accessing Significantly More Apps Than Baseline | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - Patient APT: Multi-Channel Low & Slow Exfiltration | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZPA/ZIA - Perfect Impostor: Account Takeover Hiding Within Normal Traffic | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Zscaler ZIA - APT Control Evasion: Agent Tampering and Visibility Degradation | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |

## DNSEvents

| Name | Severity | Description |
|---|---|---|
| DNS Tunneling via High-Volume TXT Record Queries | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNS C2 Beaconing — Low-TTL Periodic Domain Lookups | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| ClickFix nslookup Payload Delivery via DNS | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DGA — High-Entropy Subdomain Pattern (Domain Generation Algorithm) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNS Zone Transfer (AXFR/IXFR) from Unauthorized Internal Host | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNS Amplification Attack — Open Resolver Abuse | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNS Rebinding — Rapid TTL Change for Same Domain | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNS Data Exfiltration via Long Subdomain Labels | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| WPAD Auto-Discovery DNS Lookup Abuse | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNS-Based Internal Network Reconnaissance Sweep | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Certutil Decoding After DNS Lookup Chain (LOLBin DNS Staging) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DGA Confirmed — NXDOMAIN Flood with High-Entropy Domain Pattern | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| NULL and ANY DNS Record Type Queries — Tunneling Indicator | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNS MX Record Abuse for Payload Staging | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Subdomain Enumeration Burst — DNS Brute-Force Reconnaissance | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| DNSAdmins Privilege Escalation via DLL Injection (dnscmd /serverlevelplugindll) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| AD-Integrated DNS Wildcard Record Abuse (ADIDNS Poisoning) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |

## NonInteractiveSigninLogs

| Name | Severity | Description |
|---|---|---|
| Token Theft - Refresh Token Replay from New Location | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Non-Interactive Auth Followed by Privileged Audit Actions | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Non-Interactive Sign-In from Threat Intelligence IP | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Interactive to Non-Interactive Token Theft Pivot | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Device Code Flow Authentication Abuse | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| ROPC Authentication Detected - Credential Pass-Through Bypass | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Non-Interactive Sign-In via TOR or Anonymous Proxy | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Brute Force Success - Credential Stuffing Succeeded | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| MFA Fatigue Attack - Push Bombing Followed by Silent Token Abuse | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Stale Token Used After Password Change or Auth Method Update | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Account Takeover - Email Forwarding Rule Created After Silent Auth | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| PIM Role Activation Followed by Non-Interactive Token Use | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| OAuth App Consent Followed by Immediate Silent Authentication | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Non-Interactive Auth Followed by Bulk Data Download | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Non-Interactive Sign-Ins by Identity Protection Risky Users | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Password Spray Attack via Non-Interactive Sign-Ins | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Impossible Travel - Non-Interactive Sign-Ins from Multiple Countries | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Legacy Authentication Bypassing MFA and Conditional Access | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| High-Frequency Token Refresh - Possible Session Hijack or Automated Abuse | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| New or Rogue OAuth Application First Seen in Tenant | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Service Principal Authenticating from Anomalous IP Spread | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Non-Interactive Sign-In from High-Risk Country | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| Non-Interactive Brute Force - Single User Targeted by Multiple IPs | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |

## SigninLogs

| Name | Severity | Description |
|---|---|---|
| SigninLogs — Password Spray Attack (Single IP, Many Accounts) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Brute Force Success Chain (Possible Account Breach) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Credential Stuffing Attack (High-Velocity Invalid Credentials) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Impossible Travel (3+ Countries in 1 Hour) | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Legacy Authentication Brute Force (IMAP/POP/SMTP) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Privileged Account Under Attack (Low-Threshold Failures) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Nation State IP Sign-In Detected | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Attacker in the Middle (AiTM) Token Theft Detected | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Distributed Coordinated Attack (Botnet, 10+ IPs per User) | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — MFA Fatigue Attack (Push Bombardment) | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Slow & Low Password Spray (Multi-Day Evasion) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Account Enumeration via Error Code Fingerprinting | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Service Account Interactive Browser Sign-In | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Password Reset Followed by New-Country Sign-In (Account Takeover) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Off-Hours Sign-In by Privileged Account | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Concurrent Sessions from Multiple Countries (Same User) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Device Code Flow Authentication (Phishing Vector) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Legacy Auth First Appearance for Modern-Only Account | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — High-Frequency Repeated Sign-Ins (Automated Credential Abuse) | Medium | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — First New Country Sign-In for Privileged Account (Deterministic) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Conditional Access Policy Blocked then Successful Bypass | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |
| SigninLogs — Fresh IP Authenticating Multiple Accounts (Compromised Proxy) | High | Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense. |

---

Last synced: 03/26/2026 09:07:21

To re-import or update these rules, run:

```powershell
.\Tools\Import-CommunityRules.ps1
```

