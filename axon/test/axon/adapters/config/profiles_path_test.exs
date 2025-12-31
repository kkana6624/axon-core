defmodule Axon.Adapters.Config.ProfilesPathTest do
  use ExUnit.Case, async: false # Env vars are global

  alias Axon.Adapters.Config.ProfilesPath

  setup do
    # Create a temp directory for our "user" folder
    tmp_dir = Path.join(System.tmp_dir!(), "axon_test_" <> Integer.to_string(System.unique_integer([:positive])))
    File.mkdir_p!(tmp_dir)
    user_path = Path.join(tmp_dir, "profiles.yaml")
    
    # We need a dummy sample file in priv for testing
    priv_dir = Path.join(tmp_dir, "priv")
    File.mkdir_p!(priv_dir)
    sample_path = Path.join(priv_dir, "profiles.yaml.sample")
    File.write!(sample_path, "version: 1\nprofiles: []")

    on_exit(fn -> 
      File.rm_rf!(tmp_dir)
    end)

    %{user_path: user_path, sample_path: sample_path}
  end

  test "resolves existing file without provisioning", %{user_path: user_path} do
    File.write!(user_path, "version: 1\nprofiles: []")
    
    assert {:ok, path} = ProfilesPath.resolve(user_path: user_path)
    assert path == user_path
  end

  test "provisions sample file when no candidates exist", %{user_path: user_path, sample_path: sample_path} do
    # File doesn't exist yet
    refute File.exists?(user_path)

    # Resolve should copy sample to user_path
    assert {:ok, path} = ProfilesPath.resolve(user_path: user_path, sample_path: sample_path)
    assert path == user_path
    assert File.exists?(user_path)
    assert File.read!(user_path) =~ "version: 1"
  end
end
