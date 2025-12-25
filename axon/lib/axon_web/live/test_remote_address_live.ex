defmodule AxonWeb.TestRemoteAddressLive do
  @moduledoc false

  use AxonWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>ok</div>
    """
  end
end
