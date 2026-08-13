# frozen_string_literal: true

class Diagclean < Formula
  desc "Diagnostic collector + safe cleanup tool for helpdesk technicians"
  homepage "https://github.com/BhusanInTheShell/DiagClean"
  version "0.2.1"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.2.1/dclean-osx-arm64.tar.gz"
      sha256 "1a6578e7c8d1b940d7ac54f26f5adea7926371a19606d8f2d69759533320ce1f"
    end
    on_intel do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.2.1/dclean-osx-x64.tar.gz"
      sha256 "03a2f2448f10de090700a14bdd62f5b17dba95ad1648280a5d0feb0817dfc65c"
    end
  end

  def install
    bin.install "dclean"
    pkgshare.install "appsettings.json"
    pkgshare.install "LatoFont"

    # DiagClean.Cli/AppPaths.cs resolves appsettings.json relative to the executable's
    # own directory (AppContext.BaseDirectory) - Homebrew installs the binary into
    # bin/ separately from share/, so a symlink is needed to keep that lookup working
    # without special-casing a Homebrew install path in the app itself.
    bin.install_symlink pkgshare/"appsettings.json"
    bin.install_symlink pkgshare/"LatoFont"
  end

  test do
    assert_match "dclean", shell_output("#{bin}/dclean --help")
  end
end
