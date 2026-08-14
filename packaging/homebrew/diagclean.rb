# frozen_string_literal: true

class Diagclean < Formula
  desc "Diagnostics, cleanup, uninstall, optimize, disk analysis, and status for helpdesk technicians"
  homepage "https://github.com/BhusanInTheShell/DiagClean"
  version "0.3.1"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.3.1/dclean-osx-arm64.tar.gz"
      sha256 "ee61d93d5f2eb2a22c068c60807e3c3a21bc401cafb5e4821eeac68f6fe62c38"
    end
    on_intel do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.3.1/dclean-osx-x64.tar.gz"
      sha256 "40fae422ac9570988546c1f6302911408b699b9deffcb66707392f0f66a71f50"
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
    assert_match version.to_s, shell_output("#{bin}/dclean --version")
  end
end
