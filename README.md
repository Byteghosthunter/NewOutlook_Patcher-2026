# NewOutlookPatcher NOAB 2026

Integrated Outlook 2026 ad-blocking release.

## Components

1. **UI patch** — the known-working WebView2 worker confirmed on Outlook
   `1.2026.915.300`.
2. **HOSTS block** — blocks the four confirmed external ad endpoints without
   blocking `outlook.office.com`.

## Known-working native baseline

`NOP/worker/dllmain.cpp`

SHA256:

`DD470232B5E5BD0212B68B947834D3C910C2594660586BDEA3555DDC905F5F5B`

The v1.1 work intentionally does not modify that native worker.

## Managed HOSTS block

```text
# BEGIN NewOutlookAdBlocker-2026
0.0.0.0 msft-ssp.adnxs.com
0.0.0.0 msft-ssp-fra1.adnxs.com
0.0.0.0 eb2.3lift.com
0.0.0.0 b1t-dubdc2.outbrain.com
# END NewOutlookAdBlocker-2026
```

The application edits only its own marker block.

## Build

GitHub Actions workflow:

`Build NewOutlookPatcher NOAB v1.1 Integrated`

Expected artifact:

`NewOutlookPatcher-NOAB-2026-v1.1-x64`
