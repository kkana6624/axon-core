defmodule AxonWeb.MacroLive do
  @moduledoc false

  use AxonWeb, :live_view

  alias Axon.App.Macro.TapMacro

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="macro">macro</div>
    """
  end

  @impl true
  def handle_event("tap_macro", payload, socket) when is_map(payload) do
    case TapMacro.call(payload) do
      {:rejected, ack} ->
        {:noreply, push_event(socket, "macro_ack", ack)}

      {:accepted, ack, result_payload} ->
        Process.send_after(self(), {:emit_macro_result, result_payload}, 0)
        {:noreply, push_event(socket, "macro_ack", ack)}
    end
  end

  def handle_event("tap_macro", _payload, socket) do
    ack = %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}
    {:noreply, push_event(socket, "macro_ack", ack)}
  end

  @impl true
  def handle_info({:emit_macro_result, payload}, socket) when is_map(payload) do
    {:noreply, push_event(socket, "macro_result", payload)}
  end
end
