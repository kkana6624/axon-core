defmodule Axon.App.StaticConfigProvider do
  @moduledoc """
  Static implementation of ConfigProvider for testing.
  Does not require a process and returns deterministic values.
  """

  @behaviour Axon.App.ConfigProvider

  alias Axon.App.LoadConfig

  @impl true
  def get_config do
    # Try explicit static config first
    case Application.get_env(:axon, :static_config) do
      nil ->
        # Fallback to LoadConfig (respects AXON_PROFILES_PATH) for legacy tests
        LoadConfig.load()

      config ->
        {:ok, config}
    end
  end

  @impl true
  def subscribe, do: :ok

  @impl true
  def reload, do: :ok
end
