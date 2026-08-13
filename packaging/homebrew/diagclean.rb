# frozen_string_literal: true

class Diagclean < Formula
  desc "Diagnostics, cleanup, uninstall, optimize, disk analysis, and status for helpdesk technicians"
  homepage "https://github.com/BhusanInTheShell/DiagClean"
  version "0.3.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.3.0/dclean-osx-arm64.tar.gz"
      sha256 "af8db5f3de14a6d47a8a530d0119e9941c9f893f4c6fc8796b87b7268a96bccd"
    end
    on_intel do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.3.0/dclean-osx-x64.tar.gz"
      sha256 "6542d5056d24a3cf7a0172fbaf45c678693a76d5e69df181f6ed621c8d244709"
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
