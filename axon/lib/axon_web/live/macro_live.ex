defmodule AxonWeb.MacroLive do
  @moduledoc false

  use AxonWeb, :live_view

  alias Axon.App.ExecuteMacro

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
    case ExecuteMacro.tap_macro(payload, reply_to: self(), owner_pid: self()) do
      {:rejected, ack} ->
        {:noreply, push_event(socket, "macro_ack", ack)}

      {:accepted, ack} ->
        {:noreply, push_event(socket, "macro_ack", ack)}
    end
  end

  def handle_event("tap_macro", _payload, socket) do
    ack = %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}
    {:noreply, push_event(socket, "macro_ack", ack)}
  end

  @impl true
  def handle_event("panic", payload, socket) when is_map(payload) do
    case ExecuteMacro.panic(payload, reply_to: self()) do
      {:rejected, ack} ->
        {:noreply, push_event(socket, "macro_ack", ack)}

      {:accepted, ack} ->
        {:noreply, push_event(socket, "macro_ack", ack)}
    end
  end

  def handle_event("panic", _payload, socket) do
    ack = %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}
    {:noreply, push_event(socket, "macro_ack", ack)}
  end

  @impl true
  def handle_info({:emit_macro_result, payload}, socket) when is_map(payload) do
    {:noreply, push_event(socket, "macro_result", payload)}
  end
end
