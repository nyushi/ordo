#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <tap_repo> <formula_path> <tag_name> <version> <sha256>"
  exit 1
fi

TAP_REPO="$1"        # e.g. nyushi/homebrew-tap
FORMULA_PATH="$2"    # e.g. Casks/ordo.rb
TAG_NAME="$3"        # e.g. v1.0.0
VERSION="$4"         # e.g. 1.0.0
SHA256="$5"
TOKEN="${HOMEBREW_TAP_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  echo "HOMEBREW_TAP_TOKEN is not set; skipping tap update."
  exit 0
fi

WORKDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

git clone "https://x-access-token:${TOKEN}@github.com/${TAP_REPO}.git" "$WORKDIR/tap"

cd "$WORKDIR/tap"
mkdir -p "$(dirname "$FORMULA_PATH")"
OLD_FORMULA="Formula/ordo.rb"
if [[ -f "$OLD_FORMULA" ]]; then
  git rm -f "$OLD_FORMULA"
fi

cat > "$FORMULA_PATH" <<RUBY
cask "ordo" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/nyushi/ordo/releases/download/${TAG_NAME}/Ordo.app.zip"
  name "Ordo"
  desc "Floating org-mode scratchpad for macOS"
  homepage "https://github.com/nyushi/ordo"
  depends_on macos: ">= :ventura"

  app "Ordo.app"

  caveats <<~EOS
    Ordo watches ~/Documents/Ordo/main.org.
    Launch it once to generate the file, then edit it from any editor.
  EOS
end
RUBY

git add "$FORMULA_PATH"
if git diff --cached --quiet; then
  echo "Homebrew tap is already up-to-date."
  exit 0
fi

git commit -m "Update ordo to ${VERSION}"
git push
