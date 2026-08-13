# frozen_string_literal: true

class Diagclean < Formula
  desc "Diagnostic collector + safe cleanup tool for helpdesk technicians"
  homepage "https://github.com/BhusanInTheShell/DiagClean"
  version "0.1.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.1.0/DiagClean-osx-arm64.tar.gz"
      sha256 "01ac3cd0439c62a82033fafb39c71e879b64d9ea63f3dc7c1a83bf7930fe3ff6"
    end
    on_intel do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.1.0/DiagClean-osx-x64.tar.gz"
      sha256 "afa919b4f0eb9915be6bb1a39ccecf7a4749931523cb479133e5d2906622e86d"
    end
  end

  def install
    bin.install "DiagClean"
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
    assert_match "DiagClean", shell_output("#{bin}/DiagClean --help")
  end
end
