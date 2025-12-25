defmodule Axon.Adapters.Config.YamlConfigGateway do
  @moduledoc false

  @type error_reason :: term()

  @spec read_file(Path.t()) :: {:ok, map()} | {:error, error_reason()}
  def read_file(path) when is_binary(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, %{} = map} ->
        {:ok, map}

      {:ok, other} ->
        {:error, {:invalid_yaml_root, other}}

      {:error, reason} ->
        {:error, {:yaml_read_failed, reason}}
    end
  end
end
