defmodule Spotless.MixProject do
  use Mix.Project

  def project do
    [
      app: :spotless,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      erlc_paths: ["src", "gen"],
      compilers: [:gleam | Mix.compilers()],
      deps: deps()
    ]
  end

  def application do
    [
      # NOTE gleam_http should be required by cowboy
      extra_applications: [:logger, :gleam_http],
      mod: {Spotless.Application, []}
    ]
  end

  defp deps do
    [
      {:mix_gleam, "~> 0.1.0"},
      {:gleam_stdlib, "~> 0.14.0", override: true},
      # {:gleam_beam, "~> 0.1.0"},
      {:gleam_beam, github: "midas-framework/beam", override: true},
      {:gleam_cowboy, "~> 0.2.2"},
    #   Doesnt work on gleam 14
    #   {:gleam_file, "~> 0.1.0"},
      {:gleam_http, "~> 2.0", override: true},
      {:gleam_httpc, "~> 1.0.1", override: true},
      {:gleam_json, "~> 0.1.0"},
      {:perimeter, github: "midas-framework/perimeter"},
    ]
  end
end