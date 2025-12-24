defmodule Axon.Adapters.Config.ProfilesPath do
  @moduledoc false

  @default_env_var "AXON_PROFILES_PATH"

  @spec resolve(keyword()) :: {:ok, Path.t()} | {:error, {:profiles_not_found, Path.t()}}
  def resolve(opts \\ []) do
    env_var = Keyword.get(opts, :env_var, @default_env_var)
    priv_path = Keyword.get(opts, :priv_path, default_priv_path())
    user_path = Keyword.get(opts, :user_path, default_user_path())

    candidates =
      [System.get_env(env_var), priv_path, user_path]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case Enum.find(candidates, &File.exists?/1) do
      nil ->
        missing = List.first(candidates) || ""
        {:error, {:profiles_not_found, missing}}

      path ->
        {:ok, path}
    end
  end

  defp default_priv_path do
    priv_dir = :code.priv_dir(:axon)

    case priv_dir do
      dir when is_list(dir) -> Path.join(List.to_string(dir), "profiles.yaml")
      dir when is_binary(dir) -> Path.join(dir, "profiles.yaml")
      _ -> ""
    end
  end

  defp default_user_path do
    # MVP: keep it simple and overrideable via opts.
    ""
  end
end
