defmodule Axon.Adapters.Config.ProfilesPath do
  @moduledoc false

  @default_env_var "AXON_PROFILES_PATH"

  @spec resolve(keyword()) :: {:ok, Path.t()} | {:error, {:profiles_not_found, Path.t()}}
  def resolve(opts \\ []) do
    env_var = Keyword.get(opts, :env_var, @default_env_var)
    priv_path = Keyword.get(opts, :priv_path, default_priv_path())
    user_path = Keyword.get(opts, :user_path, default_user_path())
    sample_path = Keyword.get(opts, :sample_path, default_sample_path())
    provision? = Keyword.get(opts, :provision, true)

    candidates =
      [System.get_env(env_var), priv_path, user_path]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case Enum.find(candidates, &File.exists?/1) do
      nil ->
        if provision? do
          provision_sample(user_path, sample_path)
        else
          missing = List.first(candidates) || user_path
          {:error, {:profiles_not_found, missing}}
        end

      path ->
        {:ok, path}
    end
  end

  defp provision_sample(target_path, sample_path) do
    if is_binary(target_path) and target_path != "" and 
       is_binary(sample_path) and File.exists?(sample_path) do
      
      File.mkdir_p!(Path.dirname(target_path))
      File.copy!(sample_path, target_path)
      {:ok, target_path}
    else
      {:error, {:profiles_not_found, target_path}}
    end
  rescue
    _ -> {:error, {:profiles_not_found, target_path}}
  end

  defp default_priv_path do
    priv_dir = :code.priv_dir(:axon)

    case priv_dir do
      dir when is_list(dir) -> Path.join(List.to_string(dir), "profiles.yaml")
      dir when is_binary(dir) -> Path.join(dir, "profiles.yaml")
      _ -> ""
    end
  end

  defp default_sample_path do
    priv_dir = :code.priv_dir(:axon)

    case priv_dir do
      dir when is_list(dir) -> Path.join(List.to_string(dir), "profiles.yaml.sample")
      dir when is_binary(dir) -> Path.join(dir, "profiles.yaml.sample")
      _ -> ""
    end
  end

  defp default_user_path do
    case :os.type() do
      {:win32, _} ->
        local_app_data = System.get_env("LOCALAPPDATA") || System.get_env("APPDATA")
        if local_app_data do
          Path.join([local_app_data, "Axon", "profiles.yaml"])
        else
          ""
        end
      _ ->
        ""
    end
  end
end
