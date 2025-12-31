defmodule Axon.App.Setup.GetNicCapabilities do
  @moduledoc """
  UseCase to retrieve WLAN interface capabilities.
  """

  alias Axon.Adapters.MacroEngine.NifEngine

  @spec execute(keyword()) :: {:ok, list(map())} | {:error, term()}
  def execute(opts \\ []) do
    engine = Keyword.get(opts, :engine, NifEngine)
    engine.get_wlan_interfaces()
  end
end
