defmodule Axon.Adapters.Config.KeycodesGateway do
  @moduledoc false

  @type key :: String.t()

  @spec read_default() :: {:ok, MapSet.t(key())} | {:error, term()}
  def read_default do
    read_from_path(default_path())
  end

  @spec read_from_path(Path.t()) :: {:ok, MapSet.t(key())} | {:error, term()}
  def read_from_path(path) when is_binary(path) do
    case File.read(path) do
      {:ok, json} ->
        decode(json)

      {:error, _} ->
        {:error, {:keycodes_not_found, path}}
    end
  end

  defp decode(json) when is_binary(json) do
    with {:ok, %{"version" => 1, "keys" => keys}} <- Jason.decode(json),
         true <- is_list(keys) do
      valid_keys =
        Enum.reduce_while(keys, MapSet.new(), fn
          %{"name" => name}, acc when is_binary(name) -> {:cont, MapSet.put(acc, name)}
          # Backward compat
          name, acc when is_binary(name) -> {:cont, MapSet.put(acc, name)}
          _, _ -> {:halt, :error}
        end)

      case valid_keys do
        :error -> {:error, :invalid_keycodes_format}
        set -> {:ok, set}
      end
    else
      {:ok, %{"version" => version}} ->
        {:error, {:unsupported_keycodes_version, version}}

      {:ok, _other} ->
        {:error, :invalid_keycodes_format}

      {:error, reason} ->
        {:error, {:invalid_keycodes_json, reason}}

      false ->
        {:error, :invalid_keycodes_format}
    end
  end

  defp default_path do
    priv_dir = :code.priv_dir(:axon)

    base =
      cond do
        is_list(priv_dir) -> List.to_string(priv_dir)
        is_binary(priv_dir) -> priv_dir
        true -> ""
      end

    Path.join(base, "keycodes.json")
  end
end
