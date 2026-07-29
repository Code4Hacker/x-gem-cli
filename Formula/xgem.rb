# Homebrew formula for xgem.
# Lives here for convenience; for `brew install` to work, this file needs to
# live in a separate tap repo named `homebrew-xgem` (e.g. github.com/<owner>/homebrew-xgem),
# with this file at Formula/xgem.rb in that repo.
#
# TODO once the main repo has a tagged release:
#   1. Set `url` to the release tarball, e.g.
#      https://github.com/<owner>/<repo>/archive/refs/tags/v0.1.0.tar.gz
#   2. Set `sha256` to the tarball's checksum:
#      curl -L <url> | shasum -a 256
class Xgem < Formula
  desc "Framework-aware automation CLI: scaffolds and runs clean/build/dev scripts per project type, plus a git workflow helper"
  homepage "https://github.com/<owner>/<repo>"
  url "https://github.com/<owner>/<repo>/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  def install
    bin.install "bin/xgem"
  end

  test do
    system "#{bin}/xgem"
  end
end
