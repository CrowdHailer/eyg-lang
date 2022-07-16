defmodule Spotless.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    port = port()
    IO.inspect(port)

    children = [
      %{
        id: Ace,
        start:
          {Ace.HTTP.Service, :start_link, [{Spotless.Router, nil}, [port: port, cleartext: true]]}
      }
    ]

    opts = [strategy: :one_for_one, name: Spotless.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp port() do
    with raw when is_binary(raw) <- System.get_env("PORT"), {port, ""} = Integer.parse(raw) do
      port
    else
      _ -> throw(ArgumentError)
    end
  end
end
