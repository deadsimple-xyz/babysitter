class Babysitter < Formula
  desc "Supervisor for AI dev agents — keeps them on-role, unstuck, and gated"
  homepage "https://github.com/deadsimple-xyz/babysitter"
  url "https://github.com/deadsimple-xyz/babysitter/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "cfe37b6b82797b137fe922d167fe380ea4399ff5fb5f25037686964757392758"
  license "MIT"

  def install
    libexec.install "lib", "bin", "rules", "BABYSITTER.md"

    (bin/"babysitter").write <<~SH
      #!/bin/bash
      exec ruby "#{libexec}/bin/babysitter" "$@"
    SH
    chmod 0755, bin/"babysitter"
    chmod 0755, libexec/"bin/babysitter-mcp"
  end

  def caveats
    <<~EOS
      Run `hash -r` or open a new terminal, then:

        cd your-project
        babysitter .

      Requires Claude Code CLI (claude).
      API key is prompted on first run.
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/babysitter --help 2>&1", 1)
  end
end
