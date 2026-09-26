# Changelog

## v1.1 Integrated

- Keeps the confirmed-working Outlook 1.2026.915.300 native worker unchanged.
- Adds optional Windows HOSTS ad-domain blocking to the GUI.
- Reuses the proven `NewOutlookAdBlocker-2026` HOSTS markers for clean upgrades.
- Blocks only the four confirmed external ad domains.
- Explicitly excludes `outlook.office.com`.
- Preserves unrelated HOSTS entries during Apply and Uninstall.
- Adds HOSTS backups under `%ProgramData%\NewOutlookPatcher-NOAB`.
- Flushes the Windows DNS cache after managed HOSTS changes.
- Adds independent UI-patch and HOSTS on/off states plus post-apply verification.

## v1.0

First confirmed-working NOAB build on New Outlook `1.2026.915.300`.

- Preserves the successful Trace worker implementation.
- Uses AppVerifier/IFEO plus MinHook for WebView2.
- Uses `ThunkOldAddress` for loader chaining.
- Retries WebView2 hook installation after DLL loads.
- Hides the confirmed Premium/Upsell DOM row.
- Registers the script at document creation, runs immediately, and retries on navigation.
- Keeps runtime diagnostics for the first stable baseline.
