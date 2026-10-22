class RwthVpn < Formula
  desc "Lightweight RWTH Aachen VPN command-line client"
  homepage "https://amanmaurya2002.github.io/rwth-vpn/"
  url "https://github.com/amanmaurya2002/rwth-vpn/releases/download/v1.1.0/rwth-vpn-cli-1.1.0.tar.gz"
  sha256 "ca0a4a6c7bbcdf20c081a3249eac530a8791dfc3899e13568b932af4f55f669d"
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
