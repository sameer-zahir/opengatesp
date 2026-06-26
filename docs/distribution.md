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
Compress-Archive -Path OpenGateSP.exe,Start-OpenGateSP.cmd,README.md,LICENSE,CHANGELOG.md,module,gui,tools,docs,scripts -DestinationPath dist\OpenGateSP-0.10.0.zip -Force
# (run from the repo root after copying dist\OpenGateSP.exe to the repo root, or adjust paths)

gh release create v0.10.0 dist\OpenGateSP-Setup.exe dist\OpenGateSP-0.10.0.zip `
  --title "OpenGateSP 0.10.0" --notes-file release-notes.md
```

## Free code signing — SignPath Foundation (OSS)

Self-signing does **not** help end users (their PCs don't trust a certificate you made
yourself). The real free path is the **SignPath Foundation**, which gives **free code-signing
certificates to open-source projects**. OpenGateSP qualifies: public repo, OSI license (MIT).

What it buys: removes the "Unknown publisher" label and, as downloads accrue, clears SmartScreen.

**Eligibility (OpenGateSP meets the formal criteria):** OSI-approved license with no commercial
dual-licensing (MIT), not malware, actively maintained, already released in the form to be
signed (the GitHub release), functionality described on the README / download page, public repo.

**How to apply:**
1. Download the OSS Request Form (Excel) linked from **https://signpath.org/** and fill it.
   Values for OpenGateSP:
   - Project name: `OpenGateSP`
   - Repository: `https://github.com/sameer-zahir/opengatesp`
   - License: `MIT` (no dual-licensing)
   - Description: free, open-source ShareGate alternative for SharePoint Online — file-share
     migration, a pre-migration readiness check, permissions/external-sharing reports, site
     provisioning, scheduled governance reports. Windows GUI + PowerShell module + MCP server.
   - Download / releases page: `https://github.com/sameer-zahir/opengatesp/releases`
   - Build system: GitHub Actions
   - Artifacts to sign: `OpenGateSP-Setup.exe` and `OpenGateSP.exe`
   - Maintainer / contact: Sameer Zahir — sameerzahir97@gmail.com
2. Email the completed form to the address SignPath lists on the site.
3. They review and verify the project's **reputation** and that you control the repo.
   **Heads-up:** the repo is brand new (0 stars), and the reputation check can mean a fresh
   project is asked to come back once it has some traction. It costs nothing to apply, so apply
   — just don't block releases on it.
4. Once approved: SignPath provisions an OV certificate (the private key lives on their HSM —
   you never touch it). Add a signing step to the release workflow (their GitHub Action uploads
   the artifact, SignPath signs it, the workflow attaches it), then drop the "unsigned" note
   from the README.

Keep shipping unsigned in the meantime — the one-click "More info → Run anyway" is normal for
admin tools, and winget (below) sidesteps it entirely.

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
   wingetcreate update SameerZahir.OpenGateSP --version 0.10.0 `
     --urls https://github.com/sameer-zahir/opengatesp/releases/download/v0.10.0/OpenGateSP-Setup.exe `
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
