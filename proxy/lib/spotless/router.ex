defmodule Spotless.Router do
  use Raxx.SimpleServer
  # @sse_mime_type ServerSentEvent.mime_type()

  def handle_request(%Raxx.Request{path: ["register"]}, _) do
    Raxx.response(:ok)
    |> Raxx.set_body(client_id())
  end

  def handle_request(%Raxx.Request{path: ["request", client_id]}, _) do
    :yes = :global.re_register_name({Spotless.Client, client_id}, self())

    receive do
      {:request, value} ->
        IO.inspect(value)
        # code
    end

    Raxx.response(:ok)
    |> Raxx.set_body("got response")
  end

  def handle_request(request, _) do
    case String.split(Raxx.request_host(request)) do
      [client_id, "spotless", "run"] when client_id != "api" ->
        pid = :global.whereis_name({Spotless.Client, client_id})
        send(pid, {:request, request})

        Raxx.response(:ok)
        |> Raxx.set_body("I've forwarded it")

    #   other ->
    #     IO.inspect(other)
    end
  end

  # just hardcode the spotless domain

  # connect event source
  # reregister name

  # need two long polls but the second will wipe out the first
  # debugging see how often it happens
  # no buffer

  # fetch
  # regardless of output start a new one.

  # connect
  # set cookie show id in the client
  # could leave in memory without cookie
  # start the event source
  # let's not even bother with catching them all
  # request get an encoded pid to reply too
  # Raxx router works with long poll and waiting

  def client_id do
    <<id::binary-6, _::binary>> = Base.encode32(:crypto.strong_rand_bytes(5))
    id
  end
end
