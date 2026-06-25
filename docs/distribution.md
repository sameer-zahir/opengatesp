# Distribution, signing & winget

How OpenGateSP gets to users, and how to make the "Windows protected your PC" warning go
away **without paying for a certificate**.

## Build the release artifacts

```powershell
pwsh installer\Build-Installer.ps1
# Produces:
#   dist\OpenGateSP.exe          (portable launcher, used inside the zip)
#   dist\OpenGateSP-Setup.exe    (the installer)
```

Then bundle the portable zip (the unzip-and-run option) and cut the release:

```powershell
# Zip the app tree for the portable download (exclude dev-only folders):
Compress-Archive -Path OpenGateSP.exe,Start-OpenGateSP.cmd,README.md,LICENSE,CHANGELOG.md,module,gui,tools,docs,scripts -DestinationPath dist\OpenGateSP-0.2.0.zip -Force
# (run from the repo root after copying dist\OpenGateSP.exe to the repo root, or adjust paths)

gh release create v0.2.0 dist\OpenGateSP-Setup.exe dist\OpenGateSP-0.2.0.zip `
  --title "OpenGateSP 0.2.0" --notes-file release-notes.md
```

## Free code signing — SignPath Foundation (OSS)

Self-signing does **not** help end users (their PCs don't trust a certificate you made
yourself). The real free path is the **SignPath Foundation**, which gives **free code-signing
certificates to open-source projects**. OpenGateSP qualifies: public repo, OSI license (MIT).

What it buys: removes the "Unknown publisher" label and, as downloads accrue, clears SmartScreen.

Steps:
1. Apply at **https://signpath.org/** (SignPath Foundation → free code signing for OSS). You'll
   describe the project and link the GitHub repo.
2. Once approved, SignPath provisions a certificate + a signing policy for the project.
3. Wire signing into CI (GitHub Actions): the release workflow uploads the built
   `OpenGateSP-Setup.exe` (and `OpenGateSP.exe`) to SignPath via their GitHub Action / API;
   SignPath signs and returns the artifact, which the workflow then attaches to the release.
4. Update this repo's README to drop the "unsigned" note once signing is live.

Approval isn't instant and they vet the project, so treat this as a parallel track — keep
shipping unsigned in the meantime (one-click "More info → Run anyway", normal for admin tools).

## winget — `winget install OpenGateSP`

The manifests live in `installer\winget\` (identifier **`SameerZahir.OpenGateSP`**). Installing
through winget doesn't hit the browser SmartScreen wall, so this is the slickest free path.

After a release is published:
1. Compute the installer hash and paste it into the installer manifest:
   ```powershell
   (Get-FileHash dist\OpenGateSP-Setup.exe -Algorithm SHA256).Hash
   ```
2. Validate and test locally:
   ```powershell
   winget validate installer\winget
   winget install --manifest installer\winget   # installs from the local manifest
   ```
3. Submit a PR to **microsoft/winget-pkgs** (easiest with `wingetcreate`):
   ```powershell
   winget install Microsoft.WingetCreate
   wingetcreate update SameerZahir.OpenGateSP --version 0.2.0 `
     --urls https://github.com/sameer-zahir/opengatesp/releases/download/v0.2.0/OpenGateSP-Setup.exe `
     --submit
   ```
   Moderators review it; once merged, `winget install OpenGateSP` works for everyone.

## Microsoft Store (later — noted, not now)

The Store is the only path with **zero SmartScreen, ever** (Microsoft signs the package), plus
auto-updates and one-click install — the most "it just installs" experience.

- Cost: a **one-time ~$19** individual developer account (not a recurring cert).
- Packaging: wrap the app as **MSIX**.
- Trade-off the user flagged: Store submission means **certification review + Store policies**,
  so it's deferred for now. Revisit once the project has traction; the $19 itself is fine.

## Quick comparison

| Path | Cost | SmartScreen warning | Effort |
|---|---|---|---|
| Unsigned installer (today) | free | one-time "Run anyway" | done |
| SignPath OSS signing | free | gone (after reputation builds) | apply + CI |
| winget | free | bypassed | manifest + PR |
| Microsoft Store (MSIX) | ~$19 once | never | packaging + review |
