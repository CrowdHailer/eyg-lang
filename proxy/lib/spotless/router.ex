defmodule Spotless.Router do
    use Raxx.SimpleServer
    # @sse_mime_type ServerSentEvent.mime_type()

    def handle_request(_, _) do
        Raxx.response(:ok)
        |> Raxx.set_body("Hello")
    end
end