defmodule AxonWeb.SetupController do
  use AxonWeb, :controller

  alias Axon.Adapters.Config.ProfilesPath
  alias Axon.App.LoadConfig

  def index(conn, _params) do
    config_result = LoadConfig.load()
    profiles_path_result = ProfilesPath.resolve()

    render(conn, :index,
      config_result: config_result,
      profiles_path_result: profiles_path_result,
      env_var: "AXON_PROFILES_PATH",
      env_value: System.get_env("AXON_PROFILES_PATH")
    )
  end
end
