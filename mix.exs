defmodule CiscoSNMP.Mixfile do
  use Mix.Project

  def project do
    [app: :cisco_snmp_ex,
     version: "0.0.1",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {   
        :net_snmp_ex,
        git: "https://github.com/jonnystorm/net-snmp-elixir.git",
        ref: "56ee97f65c"
      },  
      {   
        :snmp_mib_ex,
        git: "https://github.com/jonnystorm/snmp-mib-elixir.git",
        ref: "efd4dcc17e"
      }
    ]
  end
end
