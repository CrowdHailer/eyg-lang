defmodule Spotless.MixProject do
  use Mix.Project

  def project do
    [
      app: :spotless,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      erlc_paths: ["src", "gen"],
      compilers: [:gleam | Mix.compilers()],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Spotless.Application, []}
    ]
  end

  defp deps do
    [
      {:mix_gleam, "~> 0.1.0"},
      {:gleam_stdlib, "~> 0.16.0"},
      {:ace, "~> 0.19.0"},
      {:jason, "~> 1.2"},
    ]
  end
end
