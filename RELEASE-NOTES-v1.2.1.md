# NewOutlookPatcher NOAB 2026 — v1.2.1

## Stable Outlook UI patch
The known-working Outlook/WebView2 worker is unchanged.

Worker source SHA256:

`DD470232B5E5BD0212B68B947834D3C910C2594660586BDEA3555DDC905F5F5B`

## Kaspersky-aware HOSTS handling

The HOSTS checkbox remains integrated into the GUI.

HOSTS changes are still performed by the separate PowerShell helper based on
the proven v0.6 implementation. The patcher does not modify HOSTS ownership or
ACLs.

If an elevated HOSTS write is denied:

- the helper checks Windows Security Center for Kaspersky;
- it checks loaded file-system filters for Kaspersky `klif` / `klbackupflt`;
- when Kaspersky protection is detected, the helper exits with code 23;
- the CMD and GUI explain that Kaspersky protection should be paused
  temporarily, the HOSTS action retried, and protection re-enabled afterwards.

NOAB does **not** disable Kaspersky automatically.

A non-Kaspersky security/filter denial returns exit code 24.

Release files that must stay together:

- `NewOutlookPatcher-NOAB-2026-v1.2.1.exe`
- `NOAB-HOSTS-INSTALL.cmd`
- `NOAB-HOSTS-REMOVE.cmd`
- `NOAB-Hosts.ps1`
- `domains.txt`
