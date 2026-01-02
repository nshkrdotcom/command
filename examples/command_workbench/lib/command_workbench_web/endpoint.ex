defmodule CommandWorkbenchWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :command_workbench

  @session_options [
    store: :cookie,
    key: "_command_workbench_key",
    signing_salt: "command_signing_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/",
    from: :command_workbench,
    gzip: false,
    only: CommandWorkbenchWeb.static_paths()
  )

  if code_reloading? do
    plug(Phoenix.CodeReloader)
    plug(Phoenix.LiveReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(CommandWorkbenchWeb.Router)
end
