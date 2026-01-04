defmodule Axon.App.Keycodes do
  @moduledoc false

  @version 1

  @spec expected_json() :: String.t()
  def expected_json do
    keys_json =
      try do
        Axon.Adapters.MacroEngine.NifEngine.dump_keycodes_nif()
      rescue
        _ -> "[]"
      catch
        _, _ -> "[]"
      end

    keys = Jason.decode!(keys_json)

    obj =
      Jason.OrderedObject.new([
        {"version", @version},
        {"keys", keys}
      ])

    Jason.encode!(obj, pretty: true) <> "\n\n"
  end

  @spec keys() :: [String.t()]
  def keys do
    case Jason.decode(expected_json()) do
      {:ok, %{"keys" => keys}} -> Enum.map(keys, fn %{"name" => name} -> name end)
      _ -> []
    end
  end

  @spec default_path() :: Path.t()
  def default_path do
    priv_dir = :code.priv_dir(:axon)

    base =
      cond do
        is_list(priv_dir) -> List.to_string(priv_dir)
        is_binary(priv_dir) -> priv_dir
        true -> ""
      end

    Path.join(base, "keycodes.json")
  end

  @spec repo_path() :: Path.t()
  def repo_path do
    Path.expand("priv/keycodes.json", File.cwd!())
  end

  @spec check_file(Path.t()) ::
          :ok
          | {:error, {:diff, expected :: String.t(), actual :: String.t()}}
          | {:error, {:read_error, Path.t(), term()}}
  def check_file(path \\ default_path()) when is_binary(path) do
    case File.read(path) do
      {:ok, actual} ->
        expected = expected_json()

        if actual == expected do
          :ok
        else
          {:error, {:diff, expected, actual}}
        end

      {:error, reason} ->
        {:error, {:read_error, path, reason}}
    end
  end
end
