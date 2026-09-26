# GitHub upload package

This ZIP contains the clean source set intended for the GitHub repository.

Important:
- Upload the CONTENTS of this folder to the repository root.
- Keep `.github/workflows/build-patcher.yml` at exactly that path.
- Do not commit generated `x64`, `bin`, `obj`, `dist`, or MinHook `.lib` files.
- The known-working native worker is protected by a SHA256 guard in the workflow.

Expected GitHub Actions workflow:
`Build NewOutlookPatcher NOAB v1.1 Integrated`

Expected artifact:
`NewOutlookPatcher-NOAB-2026-v1.1-x64`
