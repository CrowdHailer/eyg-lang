FROM ghcr.io/gleam-lang/gleam:v0.14.4-elixir

# NOTE these two should not be needed if using the midas container
WORKDIR /opt/app
RUN mix local.hex --force && mix local.rebar --force

COPY . .
RUN mix deps.get
# NOTE there is a bug which means gleam_otp is not compiling properly
RUN gleam build && mix compile
# Unsure why this step is necessay with compilation orders with Gleam + Mix
RUN mix test --no-start --exclude test

CMD ["./bin/start"]