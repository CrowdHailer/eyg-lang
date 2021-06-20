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
      {:request, forwarded, response_id} ->
        %Raxx.Request{method: method, raw_path: path, query: query, headers: headers, body: body} =
          forwarded

        Raxx.response(:ok)
        |> Raxx.set_header("content-type", "application/json")
        |> Raxx.set_body(
          Jason.encode!(%{
            method: method,
            raw_path: path,
            query: query,
            headers: Enum.into(headers, %{}),
            body: body,
            response_id: response_id
          })
        )
    after
      25_000 ->
        Raxx.response(:no_content)
    end
  end

  def handle_request(%Raxx.Request{path: ["response", response_id], body: body}, _) do
      case :global.whereis_name({Spotless.Response, client_id}) do
          pid when is_pid(pid) ->
            send(pid, {:response, body})

            Raxx.response(:ok)
            |> Raxx.set_body("I've replied")

          :undefined ->
            Raxx.response(:ok)
            |> Raxx.set_body("no pid found")
        end
  end

  def handle_request(request, _) do
    case String.split(Raxx.request_host(request), ".") do
      [client_id, "spotless", "run"] when client_id != "api" ->
        case :global.whereis_name({Spotless.Client, client_id}) do
          pid when is_pid(pid) ->
            response_id = response_id()
            :yes = :global.re_register_name({Spotless.Response, response_id}, self())
            send(pid, {:request, request, response_id})

            receive do
                {:response, body} ->
            Raxx.response(:ok)
            |> Raxx.set_body(body)
            end
            

          :undefined ->
            Raxx.response(:ok)
            |> Raxx.set_body("no pid found")
        end

      _ ->
        Raxx.response(:ok)
        |> Raxx.set_body("I've not forward it " <> Raxx.request_host(request))
    end
  end

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


  def response_id do
    Base.encode32(:crypto.strong_rand_bytes(5))
  end
end
