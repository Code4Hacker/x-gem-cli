# Homebrew formula for xgem.
# Lives here for convenience; for `brew install` to work, this file needs to
# live in a separate tap repo named `homebrew-xgem` (e.g. github.com/Code4Hacker/homebrew-xgem),
# with this file at Formula/xgem.rb in that repo.
#
# TODO once x-gem-cli has a tagged release:
#   1. Set `url` to the release tarball, e.g.
#      https://github.com/Code4Hacker/x-gem-cli/archive/refs/tags/v2.0.0-alpha.tar.gz
#   2. Set `sha256` to the tarball's checksum:
#      curl -L <url> | shasum -a 256
#
# install() preserves the same bin/lib/templates layout as the repo itself
# (all under `prefix`, with bin/xgem a sibling of lib/ and templates/) so
# bin/xgem's own runtime path resolution (XGEM_HOME) works unchanged across
# npm, Homebrew, and a plain git checkout.
class Xgem < Formula
  desc "Framework-aware automation CLI: scaffolds and runs clean/build/dev scripts per project type, an environment doctor, a SwiftPM-aware iOS build engine, and a git workflow helper"
  homepage "https://github.com/Code4Hacker/x-gem-cli"
  url "https://github.com/Code4Hacker/x-gem-cli/archive/refs/tags/v2.0.0-alpha.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  def install
    prefix.install "lib"
    prefix.install "templates"
    bin.install "bin/xgem"
  end

  test do
    system "#{bin}/xgem", "--version"
  end
end
