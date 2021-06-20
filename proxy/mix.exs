defmodule Spotless.MixProject do
  use Mix.Project

  def project do
    [
      app: :spotless,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
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
      {:ace, "~> 0.19.0"},
      {:server_sent_event, "~> 1.0"}
    ]
  end
end
