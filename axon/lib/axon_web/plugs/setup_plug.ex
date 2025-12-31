defmodule AxonWeb.Plugs.SetupPlug do
  @moduledoc false

  import Plug.Conn

  defp config_provider, do: Application.get_env(:axon, :config_provider)

  @setup_path "/setup"
  @test_env Mix.env() == :test

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    if bypass?(conn) do
      conn
    else
      case config_provider().get_config() do
        {:ok, _config} ->
          conn

        {:error, _reason} ->
          conn
          |> Phoenix.Controller.redirect(to: @setup_path)
          |> halt()
      end
    end
  end

  defp bypass?(%Plug.Conn{request_path: @setup_path}), do: true

  defp bypass?(%Plug.Conn{request_path: path}) when is_binary(path) do
    @test_env and String.starts_with?(path, "/__test__/")
  end
end
