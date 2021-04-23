defmodule Spotless.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    port = port()

    children = [
      %{
        id: :cowboy,
        start: {:spotless@web@endpoint, :start, [port]}
      }
    ]

    config = :spotless@config.from_env()
    # nil = :gleam@beam@logger.add_handler(&:spotless@logger.handle(config, &1, &2, &3))
    
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