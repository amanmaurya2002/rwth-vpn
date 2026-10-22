class RwthVpn < Formula
  desc "Lightweight RWTH Aachen VPN command-line client"
  homepage "https://amanmaurya2002.github.io/rwth-vpn/"
  url "https://github.com/amanmaurya2002/rwth-vpn/releases/download/v1.1.0/rwth-vpn-cli-1.1.0.tar.gz"
  sha256 "f90ba56d0e58e9fe7e1879a8a8a4f1add0d2ee84334dc46a7c97ad77b32207fb"
  version "1.1.0"
  license "MIT"

  def install
    libexec.install "rwth-vpn-cli"
    libexec.install "resources"
    (bin/"rwth-vpn").write <<~SH
      #!/bin/sh
      export RWTH_VPN_RESOURCE_ROOT="#{libexec}/resources"
      exec "#{libexec}/rwth-vpn-cli" "$@"
    SH
  end

  test do
    assert_match "Usage: rwth-vpn", shell_output("#{bin}/rwth-vpn help")
  end
end
