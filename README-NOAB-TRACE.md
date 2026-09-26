# NewOutlookPatcher NOAB Trace — 2026.09.26.05

This build is for the current Outlook 1.2026.915.300 investigation.

It keeps the PR #19 MinHook approach and the confirmed
`MessageAdKeyOutlookUpSell` DirectJS payload, but adds trace logging so the
failure point is visible instead of guessed.

Runtime log:

`%LOCALAPPDATA%\NewOutlookAdBlocker\NewOutlookPatcher-NOAB.log`

Important trace stages:

- `WebView2 MinHook enabled successfully`
- `CreateCoreWebView2EnvironmentWithOptions intercepted`
- `EnvironmentCompleted intercepted`
- `QueryInterface ICoreWebView2Environment10`
- `CreateCoreWebView2Controller intercepted`
- `ControllerCompleted intercepted`
- `AddScriptToExecuteOnDocumentCreated`
- `ExecuteScript(...) completed ... result=...`
- `NavigationCompleted`

The JavaScript returns the number of Premium/Upsell elements found, so a line
such as `result=1` proves that the relevant WebView received the script and
matched the selector.

This build deliberately does NOT patch
`CreateCoreWebView2ControllerWithOptions` yet. If the log reaches
`EnvironmentCompleted`, reports Environment10 support, but never reaches
`CreateCoreWebView2Controller`, that is strong evidence that the current
Outlook build is using a newer controller creation path. That becomes the next
targeted change.
