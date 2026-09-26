# NewOutlookPatcher NOAB PR19 DirectJS

This test build combines:

- the existing NOAB DirectJS Premium/Upsell payload;
- the AppVerifier installation path already proven to load NewOutlookPatcher.dll;
- the WebView2 hooking strategy from valinet/NewOutlookPatcher PR #19,
  commit df9160e (nicbedford);
- MinHook v1.3.4, built from the official MinHook source during GitHub Actions.

Why this build exists:

The diagnostic on Outlook 1.2026.915.300 showed that NewOutlookPatcher.dll is
installed, IFEO/AppVerifier is active, the Premium selector is inside the DLL,
and the DLL is loaded into olk.exe. Therefore the remaining failure point is
the legacy WebView2 IAT hook.

PR #19 replaces that legacy IAT patch with a MinHook detour for
CreateCoreWebView2EnvironmentWithOptions.

The PR author originally targeted Outlook 1.2026.428.200 and later reported it
working with 1.2026.617.600. Outlook 1.2026.915.300 is newer, so this remains a
test rather than a guaranteed fix.

Expected workflow:
Build NewOutlookPatcher NOAB PR19 DirectJS

Expected artifact:
NewOutlookPatcher-NOAB-PR19-DirectJS-x64
