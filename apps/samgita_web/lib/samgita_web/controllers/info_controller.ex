defmodule SamgitaWeb.InfoController do
  use SamgitaWeb, :controller

  @mix_env to_string(Mix.env())

  def index(conn, _params) do
    json(conn, %{
      app: "samgita",
      version: Application.spec(:samgita, :vsn) |> to_string(),
      elixir: System.version(),
      otp: :erlang.system_info(:otp_release) |> to_string(),
      environment: Application.get_env(:samgita_web, :env, @mix_env) |> to_string(),
      umbrella_apps: umbrella_apps(),
      phoenix: Application.spec(:phoenix, :vsn) |> to_string(),
      endpoint: to_string(SamgitaWeb.Endpoint.url())
    })
  end

  defp umbrella_apps do
    for app <- [:samgita_provider, :samgita, :samgita_memory, :samgita_web],
        vsn = Application.spec(app, :vsn) do
      %{name: app, version: to_string(vsn)}
    end
  end
end
