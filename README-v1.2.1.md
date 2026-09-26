# NewOutlookPatcher NOAB 2026

Open-source ad blocking and UI cleanup for **New Outlook for Windows**.

The project combines the known-working New Outlook WebView2 patch with an optional Windows `HOSTS` block for confirmed Outlook advertising endpoints.

> Tested baseline: **New Outlook 1.2026.915.300**  
> Current release: **v1.2.1**

---

## What it does

NewOutlookPatcher NOAB has two independent parts.

### 1. Outlook UI patch

The native patcher loads into `olk.exe` through the Windows Application Verifier / IFEO mechanism and hooks the WebView2 environment used by New Outlook.

It hides the confirmed Premium / Upsell row identified by:

```text
[data-message-ad-id^="MessageAdKeyOutlookUpSell"]
```

The current native worker is the confirmed-working baseline and is intentionally kept unchanged.

### 2. Windows HOSTS ad blocking

The optional HOSTS feature blocks the confirmed external ad endpoints:

```text
msft-ssp.adnxs.com
msft-ssp-fra1.adnxs.com
eb2.3lift.com
b1t-dubdc2.outbrain.com
```

`outlook.office.com` is **not** blocked.

The HOSTS helper only manages its own marked section and preserves unrelated HOSTS entries.

---

## Important

This project does **not** unlock Microsoft 365 / Outlook Premium features and does not modify Microsoft account licensing or subscription state.

It only:

- hides the confirmed Premium / Upsell UI element;
- blocks confirmed external advertising endpoints;
- optionally enables the original F12 / DevTools functionality from NewOutlookPatcher.

---

## Release files

Keep these files together in the same folder:

```text
NewOutlookPatcher-NOAB-2026-v1.2.1.exe
NewOutlookPatcher.dll
NOAB-HOSTS-INSTALL.cmd
NOAB-HOSTS-REMOVE.cmd
NOAB-Hosts.ps1
domains.txt
```

Recommended additional release files:

```text
LICENSE
THIRD-PARTY-MINHOOK-LICENSE.txt
RELEASE-NOTES-v1.2.1.md
SHA256SUMS.txt
```

---

## Installation

1. Download the latest `NewOutlookPatcher-NOAB-2026-v1.2.1-x64` release.
2. Extract all files into the same folder.
3. Close New Outlook.
4. Start:

```text
NewOutlookPatcher-NOAB-2026-v1.2.1.exe
```

5. Select the options you want.
6. Leave **Block Outlook ad domains in Windows HOSTS** enabled if you also want network-level ad blocking.
7. Click **Apply**.
8. Confirm the Windows UAC prompt when requested.
9. If the HOSTS state needs to change, the separate HOSTS helper opens and requests Administrator approval.

New Outlook is restarted after the patch is applied.

---

## Kaspersky users

Kaspersky can protect the Windows HOSTS file through its file-system filter even when the current process is already running as Administrator.

If this happens, NOAB detects Kaspersky and reports that the HOSTS file is protected.

The helper does **not**:

- disable Kaspersky automatically;
- use `takeown`;
- use `icacls`;
- modify HOSTS ownership;
- modify HOSTS ACLs.

If Kaspersky blocks the operation:

1. Temporarily pause Kaspersky protection.
2. Run the HOSTS action again.
3. Confirm the UAC prompt.
4. Re-enable Kaspersky protection immediately afterwards.

Return code:

```text
23 = Kaspersky protection detected
24 = another security product / file-system filter is probably protecting HOSTS
```

---

## HOSTS block

The managed section looks like this:

```text
# BEGIN NewOutlookAdBlocker-2026
0.0.0.0 msft-ssp.adnxs.com
0.0.0.0 msft-ssp-fra1.adnxs.com
0.0.0.0 eb2.3lift.com
0.0.0.0 b1t-dubdc2.outbrain.com
# END NewOutlookAdBlocker-2026
```

Only this managed block is installed or removed by NOAB.

Unrelated HOSTS entries are preserved.

---

## Manual HOSTS helpers

You can also run the HOSTS actions separately.

Install the managed block:

```text
NOAB-HOSTS-INSTALL.cmd
```

Remove the managed block:

```text
NOAB-HOSTS-REMOVE.cmd
```

Both commands use the same `NOAB-Hosts.ps1` implementation used by the GUI.

---

## Uninstall

### Remove HOSTS blocking

Either:

- clear **Block Outlook ad domains in Windows HOSTS** in the GUI and click **Apply**;

or run:

```text
NOAB-HOSTS-REMOVE.cmd
```

### Remove the Outlook UI patch

Use the **Uninstall** option in NewOutlookPatcher.

The patcher removes its `NewOutlookPatcher.dll` verifier entry from the `olk.exe` IFEO configuration.

---

## Known-working Outlook baseline

The current native worker was confirmed working with:

```text
New Outlook 1.2026.915.300
```

Worker source:

```text
NOP/worker/dllmain.cpp
```

Raw SHA256:

```text
DD470232B5E5BD0212B68B947834D3C910C2594660586BDEA3555DDC905F5F5B
```

Normalized UTF-8/LF source SHA256 used by GitHub Actions:

```text
23F00ACAD0E81ACCC8FC72F4516CF33487C874D8EF1D78592B91FF57849EE02A
```

The workflow verifies this baseline before building.

---

## How the UI patch works

At a high level:

```text
olk.exe
  |
  +-- Windows IFEO / Application Verifier
        |
        +-- NewOutlookPatcher.dll
              |
              +-- WebView2 loader interception
              +-- MinHook
              +-- WebView2 controller callback
              +-- script injection at document creation
              +-- immediate execution + navigation retry
```

The injected script hides the confirmed Outlook Premium / Upsell element and observes later DOM changes.

Runtime diagnostics from the known-working baseline are written under:

```text
%LOCALAPPDATA%\NewOutlookAdBlocker\
```

---

## Building from source

The repository includes a GitHub Actions workflow:

```text
.github/workflows/build-patcher.yml
```

The workflow:

1. verifies the known-working worker source;
2. installs .NET 8 / MSBuild / NuGet;
3. builds official MinHook `1.3.4` for x64;
4. builds the native x64 worker;
5. verifies required worker markers;
6. verifies the HOSTS safety list;
7. verifies the Kaspersky-aware HOSTS helper;
8. publishes the WinForms GUI;
9. creates the release artifact.

Expected artifact:

```text
NewOutlookPatcher-NOAB-2026-v1.2.1-x64
```

The generated executable is:

```text
NewOutlookPatcher-NOAB-2026-v1.2.1.exe
```

---

## Project structure

```text
NOP/
  gui/
    Form1.cs
    Form1.Designer.cs
    Program.cs
    HostsBlocker.cs
    gui.csproj

  worker/
    dllmain.cpp
    worker.vcxproj
    MinHook.h

hosts/
  NOAB-HOSTS-INSTALL.cmd
  NOAB-HOSTS-REMOVE.cmd
  NOAB-Hosts.ps1
  domains.txt

.github/
  workflows/
    build-patcher.yml
```

---

## Safety decisions

The project intentionally does not:

- block `outlook.office.com`;
- alter Microsoft subscription or Premium entitlement state;
- automatically disable antivirus software;
- automatically change ownership or ACLs of the Windows HOSTS file;
- overwrite unrelated HOSTS entries.

The HOSTS component only manages the block between:

```text
# BEGIN NewOutlookAdBlocker-2026
# END NewOutlookAdBlocker-2026
```

---

## Compatibility

Confirmed working baseline:

```text
New Outlook for Windows 1.2026.915.300
Windows x64
```

Future Outlook updates may change WebView2 behavior or the DOM used by the Premium / Upsell element.

If a later Outlook version stops working, please include the Outlook version and relevant logs when opening an issue.

---

## Credits

This project builds on the original **NewOutlookPatcher** work and uses **MinHook** for native API hooking.

MinHook is distributed under its BSD-style license. See:

```text
THIRD-PARTY-MINHOOK-LICENSE.txt
```

The project itself is distributed under:

```text
GNU General Public License v3.0
```

See `LICENSE` for the full license text.

---

## Disclaimer

This project is an independent open-source project and is not affiliated with or endorsed by Microsoft.

Use it at your own risk. New Outlook and its internal WebView2 implementation can change through Microsoft updates.
