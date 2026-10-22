class RwthVpn < Formula
  desc "Lightweight RWTH Aachen VPN command-line client"
  homepage "https://amanmaurya2002.github.io/rwth-vpn/"
  url "https://github.com/amanmaurya2002/rwth-vpn/releases/download/v1.2.1/rwth-vpn-cli-1.2.1.tar.gz"
  sha256 "d1833a29f6533c3279c946a8fc0aa0596b67466f8a03fb40b0f8f57e995e8f1b"
  version "1.2.1"
  license "MIT"

  def install
    libexec.install "rwth-vpn-cli"
    libexec.install "resources"
    (bin/"rwth-vpn").write <<~SH
      #!/bin/sh
      export RWTH_VPN_RESOURCE_ROOT="#{libexec}/resources"
      export RWTH_VPN_INSTALL_ROOT="#{libexec}"
      export RWTH_VPN_PACKAGE_MANAGER="brew"
      exec "#{libexec}/rwth-vpn-cli" "$@"
    SH
  end

  test do
    assert_match "Usage: rwth-vpn", shell_output("#{bin}/rwth-vpn help")
  end
end
