# Homebrew cask for Quiet Keys.
# Lives in the quietapps/homebrew-tap repository as Casks/quiet-keys.rb;
# kept here as the template updated on each release.
cask "quiet-keys" do
  version "1.0.0"
  sha256 :no_check # replace with the DMG sha256 on each release

  url "https://github.com/quietapps/QuietKeys/releases/download/v#{version}/QuietKeys.dmg"
  name "Quiet Keys"
  desc "Mechanical keyboard sounds for every keystroke — free, offline, open source"
  homepage "https://github.com/quietapps/QuietKeys"

  depends_on macos: ">= :ventura"

  app "Quiet Keys.app"

  zap trash: [
    "~/Library/Application Support/Quiet Keys",
    "~/Library/Preferences/app.quiet.QuietKeys.plist",
  ]
end
