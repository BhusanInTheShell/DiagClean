# frozen_string_literal: true

class Diagclean < Formula
  desc "Diagnostic collector + safe cleanup tool for helpdesk technicians"
  homepage "https://github.com/BhusanInTheShell/DiagClean"
  version "0.2.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.2.0/dclean-osx-arm64.tar.gz"
      sha256 "0814b3c584009d7a668e04acbaf10109dac48990ec26fba16e139aefe7ffeb44"
    end
    on_intel do
      url "https://github.com/BhusanInTheShell/DiagClean/releases/download/v0.2.0/dclean-osx-x64.tar.gz"
      sha256 "e7e4815344c30d7e93842edae863a1f3b74604b935c6cc3483ef8a9b2c7713ca"
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
