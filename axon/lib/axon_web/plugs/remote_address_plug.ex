defmodule AxonWeb.Plugs.RemoteAddressPlug do
  @moduledoc false

  import Plug.Conn

  alias Axon.Adapters.Security.RemoteAddress

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, _opts) do
    config_opts = Application.get_env(:axon, :remote_address, [])

    if RemoteAddress.allowed?(conn.remote_ip, config_opts) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(403, "Forbidden")
      |> halt()
    end
  end
end
