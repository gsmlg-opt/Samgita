defmodule SamgitaWeb.InfoController do
  use SamgitaWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      app: "samgita",
      version: Application.spec(:samgita, :vsn) |> to_string(),
      elixir: System.version(),
      otp: :erlang.system_info(:otp_release) |> to_string(),
      environment: to_string(Application.get_env(:samgita_web, :env, Mix.env())),
      umbrella_apps: umbrella_apps(),
      phoenix: Application.spec(:phoenix, :vsn) |> to_string(),
      endpoint: to_string(SamgitaWeb.Endpoint.url())
    })
  end

  defp umbrella_apps do
    for app <- [:claude_api, :samgita, :samgita_memory, :samgita_web],
        vsn = Application.spec(app, :vsn) do
      %{name: app, version: to_string(vsn)}
    end
  end
end
