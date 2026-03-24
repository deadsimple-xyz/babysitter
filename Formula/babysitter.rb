class Babysitter < Formula
  desc "Supervisor for AI dev agents — keeps them on-role, unstuck, and gated"
  homepage "https://github.com/deadsimple-xyz/babysitter"
  url "https://github.com/deadsimple-xyz/babysitter/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "" # shasum -a 256 on the tarball after first release
  license "MIT"

  def install
    # Install everything under libexec preserving structure
    libexec.install "lib", "bin", "rules", "BABYSITTER.md"

    # Wrapper: babysitter
    (bin/"babysitter").write <<~SH
      #!/bin/bash
      exec ruby "#{libexec}/bin/babysitter" "$@"
    SH
    chmod 0755, bin/"babysitter"

    # Make MCP server findable (supervisor references it via babysitter_dir)
    chmod 0755, libexec/"bin/babysitter-mcp"
  end

  def caveats
    <<~EOS
      Requires:
        - Claude Code CLI (claude)
        - ANTHROPIC_API_KEY env var

      Usage:
        babysitter ../my-project "finish the tests"
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/babysitter --help 2>&1", 1)
  end
end
