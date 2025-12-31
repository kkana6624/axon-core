defmodule Axon.App.ConfigProvider do
  @moduledoc """
  Behavior for providing application configuration.
  """

  alias Axon.App.LoadConfig

  @callback get_config() :: {:ok, LoadConfig.Config.t()} | {:error, term()}
  @callback subscribe() :: :ok
  @callback reload() :: :ok | {:error, term()}
end
