defmodule Axon.Adapters.Config.ProfilesPath do
  @moduledoc false

  @default_env_var "AXON_PROFILES_PATH"

      @spec resolve(keyword()) :: {:ok, Path.t()} | {:error, {:profiles_not_found, Path.t()}}

      def resolve(opts \\ []) do

        env_var = Keyword.get(opts, :env_var, @default_env_var)

        

        # Priority order for discovery (Architecture 6.4):

        # 1. Environment variable

        # 2. Application bundled default (priv)

        # 3. User directory (user)

        

        # Options can be used to override the defaults for (2) and (3)

        priv_path = Keyword.get(opts, :priv_path, default_priv_path())

        user_path = Keyword.get(opts, :user_path, default_user_path())

        

        candidates =

          [

            System.get_env(env_var),

            priv_path,

            user_path

          ]

          |> Enum.filter(&is_binary/1)

          |> Enum.map(&String.trim/1)

          |> Enum.reject(&(&1 == ""))

          |> Enum.uniq()

    

        case Enum.find(candidates, &File.exists?/1) do

          nil ->

            # Error hint priority: env (if set), else first candidate, else user_path

            missing = System.get_env(env_var) || List.first(candidates) || user_path

            {:error, {:profiles_not_found, missing}}

    

          path ->

            {:ok, path}

        end

      end

  def default_priv_path do
    priv_dir = :code.priv_dir(:axon)

    case priv_dir do
      dir when is_list(dir) -> Path.join(List.to_string(dir), "profiles.yaml")
      dir when is_binary(dir) -> Path.join(dir, "profiles.yaml")
      _ -> ""
    end
  end

  def default_sample_path do
    priv_dir = :code.priv_dir(:axon)

    case priv_dir do
      dir when is_list(dir) -> Path.join(List.to_string(dir), "profiles.yaml.sample")
      dir when is_binary(dir) -> Path.join(dir, "profiles.yaml.sample")
      _ -> ""
    end
  end

  def default_user_path do
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
