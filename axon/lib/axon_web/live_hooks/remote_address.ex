defmodule AxonWeb.LiveHooks.RemoteAddress do
  @moduledoc false

  import Phoenix.LiveView

  alias Axon.Adapters.Security.RemoteAddress

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      peer_data = get_connect_info(socket, :peer_data)
      ip = peer_data && peer_data.address

      config_opts = Application.get_env(:axon, :remote_address, [])

      if is_tuple(ip) and RemoteAddress.allowed?(ip, config_opts) do
        {:cont, socket}
      else
        # Close immediately (treat as forbidden)
        {:halt, socket}
      end
    else
      {:cont, socket}
    end
  end
end
