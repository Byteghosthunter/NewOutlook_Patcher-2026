# NewOutlookPatcher NOAB 2026 — v1.1 Integrated

This release combines the confirmed-working Outlook UI patch with the proven
Windows HOSTS ad-domain block.

## UI layer

The native worker is byte-for-byte unchanged from the build confirmed working
with New Outlook `1.2026.915.300`.

Worker source SHA256:

`DD470232B5E5BD0212B68B947834D3C910C2594660586BDEA3555DDC905F5F5B`

The working chain remains:

AppVerifier/IFEO → MinHook → WebView2 → document-created script →
`MessageAdKeyOutlookUpSell` hiding + MutationObserver.

## Network layer

The GUI adds an optional checkbox:

`Block Outlook ad domains in Windows HOSTS`

Managed domains:

```text
0.0.0.0 msft-ssp.adnxs.com
0.0.0.0 msft-ssp-fra1.adnxs.com
0.0.0.0 eb2.3lift.com
0.0.0.0 b1t-dubdc2.outbrain.com
```

`outlook.office.com` is intentionally never added because it is an Outlook
core service.

The managed block uses the same markers as the previously tested PowerShell
blocker:

```text
# BEGIN NewOutlookAdBlocker-2026
...
# END NewOutlookAdBlocker-2026
```

This avoids duplicate blocks when upgrading from the older script.

## HOSTS safety behavior

- The whole hosts file is never replaced with an old backup during uninstall.
- Only the NOAB-managed marker block is added/removed.
- Unrelated user/application entries are preserved.
- A first/original backup and a before-last-change backup are kept in:
  `%ProgramData%\NewOutlookPatcher-NOAB\`
- DNS cache is flushed after a managed hosts change.

## Apply / Uninstall

Apply independently honors both states:
- UI patch on/off
- HOSTS blocking on/off

Uninstall removes both NOAB components while leaving unrelated hosts entries
and unrelated IFEO verifier configuration intact.
