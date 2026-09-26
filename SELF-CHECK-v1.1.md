# SELF-CHECK — v1.1 Integrated

Result: **PASS**

This is a static/source/package self-check. A native Windows compile cannot be run in this Linux execution environment; the GitHub Actions workflow remains the compile verification step.

- [x] Known-working native worker preserved — SHA256=DD470232B5E5BD0212B68B947834D3C910C2594660586BDEA3555DDC905F5F5B
- [x] HOSTS domain present: msft-ssp.adnxs.com — expected managed domain
- [x] HOSTS domain present: msft-ssp-fra1.adnxs.com — expected managed domain
- [x] HOSTS domain present: eb2.3lift.com — expected managed domain
- [x] HOSTS domain present: b1t-dubdc2.outbrain.com — expected managed domain
- [x] Exactly four managed domains — ['msft-ssp.adnxs.com', 'msft-ssp-fra1.adnxs.com', 'eb2.3lift.com', 'b1t-dubdc2.outbrain.com']
- [x] Core Outlook host excluded from managed source — outlook.office.com is not a managed domain literal
- [x] Legacy v0.6 HOSTS markers retained — prevents duplicate block on upgrade
- [x] Whole-file backup restore is not used — uninstall removes only managed marker block
- [x] HOSTS disable path does not normalize unrelated file content — only a complete managed marker block is removed
- [x] HOSTS backup before edits — ProgramData backups configured
- [x] DNS flush included — ipconfig /flushdns
- [x] Elevated apply supports independent patcher/HOSTS states — four-state command flags present
- [x] GUI has HOSTS checkbox — integrated WinForms control
- [x] Toggle-everything includes HOSTS — master toggle covers HOSTS
- [x] Apply verifies both components — post-elevation verification
- [x] GUI embeds rebuilt worker — existing resource architecture preserved
- [x] Workflow guards working worker source hash — build fails if native baseline changes
- [x] Worker builds before GUI publish — fresh worker is embedded in published GUI
- [x] Workflow has one push key — push key occurrences=1
- [x] Structural sanity: NOP/gui/HostsBlocker.cs — brace count 31 / 31
- [x] Structural sanity: NOP/gui/Program.cs — brace count 15 / 15
- [x] Structural sanity: NOP/gui/Form1.cs — brace count 60 / 60

## Important invariant

`NOP/worker/dllmain.cpp` SHA256 must remain `DD470232B5E5BD0212B68B947834D3C910C2594660586BDEA3555DDC905F5F5B` for this release.

The v1.1 integration changes the GUI/elevated installer and HOSTS management only; it does not alter the confirmed-working WebView2 hook.
