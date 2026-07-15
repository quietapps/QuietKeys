# Homebrew cask for Quiet Keys.
# Lives in the quietapps/homebrew-quietkeys repository as Casks/quietkeys.rb;
# kept here as the template updated on each release.
cask "quietkeys" do
  version "1.0.0"
  sha256 "9e80edb90ef8232d6c4ca911dc7835ee975eb12e712116b445cb133ca0684bf7"

  url "https://github.com/quietapps/QuietKeys/releases/download/#{version}/QuietKeys-#{version}.zip",
      verified: "github.com/quietapps/QuietKeys/"
  name "Quiet Keys"
  desc "Mechanical keyboard sounds for every keystroke — free, offline, open source"
  homepage "https://github.com/quietapps/QuietKeys"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: ">= :ventura"

  app "Quiet Keys.app"

  # Build is not signed with an Apple Developer ID. Make the app launchable on
  # any Mac out of the box:
  #   1. Strip ALL extended attributes (com.apple.quarantine, com.apple.macl,
  #      com.apple.provenance) so Gatekeeper does not block launch.
  #   2. Force-register the bundle with Launch Services so double-clicking from
  #      Finder / Dock launches the real binary.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Quiet Keys.app"],
                   sudo: false
    system_command "/System/Library/Frameworks/CoreServices.framework/" \
                   "Versions/A/Frameworks/LaunchServices.framework/" \
                   "Versions/A/Support/lsregister",
                   args: ["-f", "#{appdir}/Quiet Keys.app"],
                   sudo: false,
                   must_succeed: false
  end

  zap trash: [
    "~/Library/Application Support/Quiet Keys",
    "~/Library/Caches/app.quiet.QuietKeys",
    "~/Library/Preferences/app.quiet.QuietKeys.plist",
    "~/Library/Saved Application State/app.quiet.QuietKeys.savedState",
  ]

  caveats <<~EOS
    Quiet Keys is distributed unsigned. The post-install hook strips
    Gatekeeper attributes automatically, but if the app refuses to launch
    on a fresh Mac, do this once:

      1. Open Finder → /Applications
      2. Right-click "Quiet Keys.app" → Open
      3. Click "Open" in the dialog
      4. macOS remembers your choice for every future launch

    Or run this in Terminal once after install:
      xattr -cr "/Applications/Quiet Keys.app"

    Quiet Keys needs Accessibility access to hear keystrokes (listen-only,
    nothing is logged or transmitted). Grant it in System Settings →
    Privacy & Security → Accessibility when the onboarding window asks.
  EOS
end
