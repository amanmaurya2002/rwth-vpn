class RwthVpn < Formula
  desc "Lightweight RWTH Aachen VPN command-line client"
  homepage "https://amanmaurya2002.github.io/rwth-vpn/"
  url "https://github.com/amanmaurya2002/rwth-vpn/releases/download/v1.2.0/rwth-vpn-cli-1.2.0.tar.gz"
  sha256 "5029311c7dc74f12794f43d840330db88ec0bf4adee0d77b9dd525b8dce139d8"
  version "1.2.0"
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
