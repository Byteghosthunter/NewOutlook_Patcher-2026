# GitHub release steps

1. Replace the repository contents with this source tree, or overwrite the
   matching files.
2. Commit the known-working source.
3. Run `Build NewOutlookPatcher NOAB v1.0` once and verify the artifact.
4. In GitHub, create a tag:
   `v1.0-working-outlook-1.2026.915.300`
5. Create a GitHub Release from that tag.
6. Attach the built artifact ZIP from Actions to the Release if desired.

Do not delete the working tag when experimenting with future quiet/debug builds.
