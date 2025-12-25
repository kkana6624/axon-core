defmodule Axon.App.Keycodes do
  @moduledoc false

  @version 1

  # Source of truth for the generated artifact `priv/keycodes.json`.
  # Keep this list deterministic.
  @keys [
    "VK_A",
    "VK_ENTER",
    "VK_LCTRL",
    "VK_LSHIFT",
    "VK_S"
  ]

  @type key :: String.t()

  @spec keys() :: [key()]
  def keys, do: @keys

  @spec expected_json() :: String.t()
  def expected_json do
    obj = Jason.OrderedObject.new([
      {"version", @version},
      {"keys", @keys}
    ])

    Jason.encode!(obj, pretty: true) <> "\n\n"
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

  @spec check_file(Path.t()) :: :ok | {:error, {:diff, expected :: String.t(), actual :: String.t()}} | {:error, {:read_error, Path.t(), term()}}
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
