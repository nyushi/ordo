# Release workflow

This project uses a `develop` → `main` flow:

1. Work happens on `develop`. All pull requests target `develop`.
2. When ready to ship, merge `develop` into `main`, bump the version number, and tag the release as `vX.Y.Z`.
3. Push the tag. The `Release` GitHub Action will:
   - Build a release binary with `swift build -c release`.
   - Package it as `Ordo-macos.zip` and attach it to the GitHub Release.
   - Update the Homebrew tap (if configured).

## Homebrew tap automation

The release workflow can update `nyushi/homebrew-tap` automatically. Provide a personal access token with `repo` scope as the secret `HOMEBREW_TAP_TOKEN`. The workflow will rewrite `Formula/ordo.rb` with the new version and checksum, then commit and push to the tap.

If the secret is missing or the tap repository does not exist, the step is skipped. In that case, update the tap manually using the same formula template from `.github/scripts/update-homebrew-formula.sh`.
