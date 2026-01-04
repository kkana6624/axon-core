defmodule Axon.App.Setup.MdnsServer do
  @moduledoc """
  GenServer to manage mDNS lifecycle.
  """
  use GenServer

  require Logger

  alias Axon.Adapters.MacroEngine.NifEngine

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_broadcast(service_type, instance_name, port) do
    GenServer.call(__MODULE__, {:start_broadcast, service_type, instance_name, port})
  end

  def stop_broadcast do
    GenServer.call(__MODULE__, :stop_broadcast)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @impl true
  def init(opts) do
    state = %{ref: nil, engine: Keyword.get(opts, :engine, NifEngine)}
    {:ok, state, {:continue, :start_mdns}}
  end

  @impl true
  def handle_continue(:start_mdns, state) do
    config = Application.get_env(:axon, :mdns, [])

    if Keyword.get(config, :auto_start, false) do
      # Wait up to 5 seconds for NIF to be available
      if wait_for_engine(state.engine, 50) do
        type = Keyword.get(config, :service_type, "_axon-macro._tcp.local.")
        name = Keyword.get(config, :instance_name, "AxonServer")
        port = Keyword.get(config, :port, 4000)

        case state.engine.start_mdns(type, name, port) do
          {:ok, ref} ->
            Logger.info("mDNS auto-broadcast started: #{name}.#{type} on port #{port}")
            {:noreply, %{state | ref: ref}}

          {:error, _code, message} ->
            Logger.error("Failed to auto-start mDNS broadcast: #{message}")
            {:noreply, state}

          {:error, reason} ->
            Logger.error("Failed to auto-start mDNS broadcast: #{inspect(reason)}")
            {:noreply, state}
        end
      else
        Logger.warning("mDNS auto-start skipped: engine not available after timeout")
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp wait_for_engine(_engine, 0), do: false

  defp wait_for_engine(engine, retries) do
    if engine.available?() do
      true
    else
      Process.sleep(100)
      wait_for_engine(engine, retries - 1)
    end
  end

  @impl true
  def handle_call({:start_broadcast, type, name, port}, _from, state) do
    # Stop existing if any
    _ = if state.ref, do: state.engine.stop_mdns(state.ref)

    case state.engine.start_mdns(type, name, port) do
      {:ok, ref} ->
        Logger.info("mDNS broadcast started: #{name}.#{type} on port #{port}")
        {:reply, :ok, %{state | ref: ref}}

      {:error, _code, message} ->
        Logger.error("Failed to start mDNS broadcast: #{message}")
        {:reply, {:error, message}, %{state | ref: nil}}

      {:error, reason} ->
        Logger.error("Failed to start mDNS broadcast: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | ref: nil}}
    end
  end

  @impl true
  def handle_call(:stop_broadcast, _from, state) do
    if state.ref do
      state.engine.stop_mdns(state.ref)
      Logger.info("mDNS broadcast stopped")
    end

    {:reply, :ok, %{state | ref: nil}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = if state.ref, do: :running, else: :stopped
    {:reply, status, state}
  end
end
