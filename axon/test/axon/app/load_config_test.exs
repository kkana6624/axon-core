defmodule Axon.App.LoadConfigTest do
  use ExUnit.Case, async: false

  defp write_tmp!(contents) when is_binary(contents) do
    filename = "axon_profiles_#{System.unique_integer([:positive])}.yaml"
    path = Path.join(System.tmp_dir!(), filename)
    File.write!(path, contents)

    on_exit(fn ->
      _ = File.rm(path)
    end)

    path
  end

  defp with_env_var(name, value, fun) when is_binary(name) and is_function(fun, 0) do
    prev = System.get_env(name)

    if is_nil(value) do
      System.delete_env(name)
    else
      System.put_env(name, value)
    end

    try do
      fun.()
    after
      if is_nil(prev) do
        System.delete_env(name)
      else
        System.put_env(name, prev)
      end
    end
  end

  test "AXON-CONF-001 loads version=1 and profiles" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons: []
      """)

    assert {:ok, config} = Axon.App.LoadConfig.load_from_path(path)
    assert config.version == 1
    assert [%{name: "Development"}] = config.profiles
  end

  test "AXON-CONF-002 missing version returns error" do
    path =
      write_tmp!("""
      profiles:
        - name: "Development"
          buttons: []
      """)

    assert {:error, :missing_version} = Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-002 unsupported version returns error" do
    path =
      write_tmp!("""
      version: 2
      profiles:
        - name: "Development"
          buttons: []
      """)

    assert {:error, {:unsupported_version, 2}} = Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-003 missing profiles returns error" do
    path =
      write_tmp!("""
      version: 1
      """)

    assert {:error, :missing_profiles} = Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-003 empty profiles returns error" do
    path =
      write_tmp!("""
      version: 1
      profiles: []
      """)

    assert {:error, :empty_profiles} = Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-009 invalid AXON_PROFILES_PATH returns error" do
    missing = Path.join(System.tmp_dir!(), "axon_missing_#{System.unique_integer([:positive])}.yaml")

    with_env_var("AXON_PROFILES_PATH", missing, fn ->
      assert {:error, {:profiles_not_found, ^missing}} =
               Axon.App.LoadConfig.load(
                 priv_path: "",
                 user_path: ""
               )
    end)
  end

  test "AXON-CONF-010 path resolution priority is env -> priv -> user" do
    env_path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "FromEnv"
          buttons: []
      """)

    priv_path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "FromPriv"
          buttons: []
      """)

    user_path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "FromUser"
          buttons: []
      """)

    # 1) env wins
    with_env_var("AXON_PROFILES_PATH", env_path, fn ->
      assert {:ok, config} = Axon.App.LoadConfig.load(priv_path: priv_path, user_path: user_path)
      assert [%{name: "FromEnv"}] = config.profiles
    end)

    # 2) priv wins when env missing
    with_env_var("AXON_PROFILES_PATH", nil, fn ->
      assert {:ok, config} = Axon.App.LoadConfig.load(priv_path: priv_path, user_path: user_path)
      assert [%{name: "FromPriv"}] = config.profiles
    end)

    # 3) user wins when env missing and priv missing
    with_env_var("AXON_PROFILES_PATH", nil, fn ->
      assert {:ok, config} = Axon.App.LoadConfig.load(priv_path: "", user_path: user_path)
      assert [%{name: "FromUser"}] = config.profiles
    end)
  end

  test "AXON-CONF-006 wait with key is invalid" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "b1"
              label: "B1"
              sequence:
                - { action: "wait", value: 10, key: "VK_A" }
      """)

    assert {:error,
            {:invalid_wait_has_key,
             %{profile: "Development", button_id: "b1", sequence_index: 0}}} =
             Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-007 wait.value out of range is invalid" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "b1"
              label: "B1"
              sequence:
                - { action: "wait", value: 10001 }
      """)

    assert {:error,
            {:invalid_wait_range,
             %{profile: "Development", button_id: "b1", sequence_index: 0, value: 10001}}} =
             Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-007 wait.value must be integer" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "b1"
              label: "B1"
              sequence:
                - { action: "wait", value: "10" }
      """)

    assert {:error,
            {:invalid_wait_value,
             %{profile: "Development", button_id: "b1", sequence_index: 0}}} =
             Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-005 action must be one of down|up|tap|wait|panic" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "b1"
              label: "B1"
              sequence:
                - { action: "hold", key: "VK_A" }
      """)

    assert {:error,
            {:invalid_action,
             %{profile: "Development", button_id: "b1", sequence_index: 0, action: "hold"}}} =
             Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-004 detects duplicate button id" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "dup"
              label: "One"
              sequence:
                - { action: "tap", key: "VK_A" }
            - id: "dup"
              label: "Two"
              sequence:
                - { action: "tap", key: "VK_A" }
      """)

    assert {:error,
            {:duplicate_button_id,
             %{profile: "Development", button_id: "dup", first_index: 0, second_index: 1}}} =
             Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-WAIT-001 wait=0 is allowed and order is preserved" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "b1"
              label: "B1"
              sequence:
                - { action: "wait", value: 0 }
                - { action: "tap", key: "VK_A" }
      """)

    assert {:ok, config} = Axon.App.LoadConfig.load_from_path(path)

    [profile] = config.profiles
    [button] = get_in(profile.raw, ["buttons"])
    [step1, step2] = get_in(button, ["sequence"])

    assert step1 == %{"action" => "wait", "value" => 0}
    assert step2 == %{"action" => "tap", "key" => "VK_A"}
  end

  test "AXON-WAIT-002 wait=10_000 is allowed" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "b1"
              label: "B1"
              sequence:
                - { action: "wait", value: 10000 }
                - { action: "tap", key: "VK_A" }
      """)

    assert {:ok, _config} = Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-WAIT-003 total wait time must not exceed 30 seconds" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "b1"
              label: "B1"
              sequence:
                - { action: "wait", value: 10000 }
                - { action: "wait", value: 10000 }
                - { action: "wait", value: 10000 }
                - { action: "wait", value: 1 }
      """)

    assert {:error,
            {:wait_total_exceeded,
             %{profile: "Development", button_id: "b1", sequence_index: 3, limit_ms: 30000, total_ms: 30001}}} =
             Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-CONF-008 sequence length over limit is invalid" do
    steps =
      for _ <- 1..257 do
        "        - { action: \"tap\", key: \"VK_A\" }"
      end
      |> Enum.join("\n")

    yaml =
      """
      version: 1
      profiles:
        - name: \"Development\"
          buttons:
            - id: \"b1\"
              label: \"B1\"
              sequence:
      #{steps}
      """

    path = write_tmp!(yaml)

    assert {:error,
            {:sequence_too_long,
             %{profile: "Development", button_id: "b1", length: 257, limit: 256}}} =
             Axon.App.LoadConfig.load_from_path(path)
  end

  test "AXON-KEY-002 unknown key returns error location" do
    path =
      write_tmp!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "save_all"
              label: "Save All"
              sequence:
                - { action: "down", key: "VK_NO_SUCH_KEY" }
      """)

    assert {:error,
            {:unknown_key,
             %{
               profile: "Development",
               button_id: "save_all",
               sequence_index: 0,
               key: "VK_NO_SUCH_KEY"
             }}} = Axon.App.LoadConfig.load_from_path(path)
  end
end
