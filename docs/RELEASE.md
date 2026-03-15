# Release workflow

This project uses a `develop` → `main` flow:

1. Work happens on `develop`. All pull requests target `develop`.
2. When ready to ship, merge `develop` into `main`, bump the version number, and tag the release as `vX.Y.Z`.
3. Push the tag. The `Release` GitHub Action will:
   - Build a release binary with `swift build -c release`.
   - Wrap it in an `Ordo.app` bundle, zip it as `Ordo.app.zip`, and attach it to the GitHub Release.
   - Update the Homebrew tap (if configured) with a cask that points to the new zip.

Setting the repository secret `RELEASE_PAT` (a PAT with `repo` scope) allows the workflow to create/update releases even when the default `GITHUB_TOKEN` lacks the required permissions.

## Homebrew tap automation

The release workflow can update `nyushi/homebrew-tap` automatically. Provide a personal access token with `repo` scope as the secret `HOMEBREW_TAP_TOKEN`. The workflow rewrites `Casks/ordo.rb` with the new version and checksum, then commits and pushes it to the tap (removing the legacy `Formula/` file if it still exists).

If the secret is missing or the tap repository does not exist, the step is skipped. In that case, update the tap manually using the same formula template from `.github/scripts/update-homebrew-formula.sh`.
