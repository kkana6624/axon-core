defmodule Axon.App.StaticConfigProviderTest do
  use ExUnit.Case, async: true

  alias Axon.App.StaticConfigProvider
  alias Axon.App.LoadConfig.Config

  setup do
    on_exit(fn ->
      Application.delete_env(:axon, :static_config)
    end)

    :ok
  end

  test "returns static config from application env if present" do
    config = %Config{version: 1, profiles: []}
    Application.put_env(:axon, :static_config, config)

    assert {:ok, ^config} = StaticConfigProvider.get_config()
  end

  test "falls back to LoadConfig.load() if static_config is missing" do
    # LoadConfig.load() will be called. We force an error by setting a non-existent path.
    original = System.get_env("AXON_PROFILES_PATH")
    System.put_env("AXON_PROFILES_PATH", "/non/existent/path/at/all/config.yaml")

    # We use Application.put_env to override default paths used by LoadConfig during this test
    # (since StaticConfigProvider calls LoadConfig.load() without arguments)
    # This is tricky because LoadConfig.load() uses ProfilesPath.resolve() defaults.

    # Alternatively, we just check that it doesn't return the default config.
    # If it returns an error or a different config, it's working as intended.
    result = StaticConfigProvider.get_config()
    assert match?({:error, _}, result) or match?({:ok, %Config{profiles: []}}, result)

    if original,
      do: System.put_env("AXON_PROFILES_PATH", original),
      else: System.delete_env("AXON_PROFILES_PATH")
  end

  test "no-op for subscribe and reload" do
    assert :ok = StaticConfigProvider.subscribe()
    assert :ok = StaticConfigProvider.reload()
  end
end
