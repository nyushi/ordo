# Ordo

Ordo is a tiny macOS helper that keeps a single org-mode file pinned on top of every Space. Edit the file from any app; Ordo just mirrors it.

## Install

```bash
brew install --cask nyushi/tap/ordo
```

## Build from source

```bash
swift run
```

The first launch creates `~/Documents/Ordo/main.org`. Toggle the floating panel from the menu bar icon and type directly into the shared file.

## Releases

Development happens on `develop`; releases happen on `main` and are tagged `vX.Y.Z`. GitHub Actions builds a signed zip containing `Ordo.app` and updates the Homebrew tap automatically. See `docs/RELEASE.md` for the flow.
