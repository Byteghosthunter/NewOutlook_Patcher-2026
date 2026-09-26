# NewOutlookPatcher NOAB DirectJS — 2026.09.26.02

This branch keeps the original 2024 NewOutlookPatcher architecture:

- original AppVerifier/IFEO installer;
- original native worker;
- original WebView2 hook chain;
- original GUI resource embedding;
- no MinHook rewrite.

The important change is the JavaScript payload executed by the worker.

The following operation was manually confirmed to hide the Outlook Premium row:

```javascript
document
  .querySelectorAll('[data-message-ad-id^="MessageAdKeyOutlookUpSell"]')
  .forEach(el => el.style.display = 'none');
```

This build now performs that behavior directly from the worker and also installs
a `MutationObserver` so Outlook cannot simply recreate the matching row later.

The checkbox:

`Disable inbox ad and Premium/Upsell row`

controls the Premium selector in the embedded worker as well.

## Build

GitHub Actions:

`Build NewOutlookPatcher NOAB DirectJS`

Expected artifact:

`NewOutlookPatcher-NOAB-DirectJS-x64`

## Test

1. Uninstall the previously installed patcher.
2. Confirm Outlook starts normally.
3. Close Outlook completely.
4. Run the new `NewOutlookPatcher-NOAB-DirectJS.exe`.
5. Keep `Disable inbox ad and Premium/Upsell row` checked.
6. Click Install/Apply.
7. Start Outlook normally.

If Premium remains visible, the selector/JavaScript is no longer the open
question: it means the original WebView2 hook path is not executing on the
current Outlook build.
