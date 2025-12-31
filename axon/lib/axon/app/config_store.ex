defmodule Axon.App.ConfigStore do
  @moduledoc """
  Production implementation of ConfigProvider.
  Holds configuration in memory, provides caching, and notifies via PubSub.
  """

  use GenServer
  @behaviour Axon.App.ConfigProvider

  alias Axon.App.LoadConfig

  @name __MODULE__
  @topic "config"

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def get_config(name \\ @name) do
    GenServer.call(name, :get_config)
  end

  @impl true
  def subscribe do
    Phoenix.PubSub.subscribe(Axon.PubSub, @topic)
  end

  @impl true
  def reload(name \\ @name) do
    GenServer.call(name, :reload)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{config: nil}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state) do
    case LoadConfig.load() do
      {:ok, config} ->
        {:noreply, %{state | config: config}}

      {:error, _reason} ->
        # 初期ロード失敗時は空の状態（nil）を保持
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    case state.config do
      nil ->
        # キャッシュがない場合は再度試行
        case LoadConfig.load() do
          {:ok, config} ->
            {:reply, {:ok, config}, %{state | config: config}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      config ->
        {:reply, {:ok, config}, state}
    end
  end

  @impl true
  def handle_call(:reload, _from, state) do
    case LoadConfig.load() do
      {:ok, config} ->
        Phoenix.PubSub.broadcast(Axon.PubSub, @topic, {:config_updated, make_ref()})
        {:reply, :ok, %{state | config: config}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
