defmodule Axon.App.ConfigStoreTest do
  use ExUnit.Case, async: true

  alias Axon.App.ConfigStore
  alias Axon.App.LoadConfig

  setup do
    # 各テストで一意の名前を使用
    test_name = Module.concat(__MODULE__, :"Store_#{System.unique_integer([:positive])}")
    
    # 環境変数を汚染しないよう一時的に退避
    original_path = System.get_env("AXON_PROFILES_PATH")
    
    on_exit(fn ->
      if original_path, do: System.put_env("AXON_PROFILES_PATH", original_path), else: System.delete_env("AXON_PROFILES_PATH")
    end)

    %{name: test_name}
  end

  defp write_tmp_profiles!(contents) do
    path = Path.join(System.tmp_dir!(), "config_store_test_#{System.unique_integer([:positive])}.yaml")
    File.write!(path, contents)
    path
  end

  test "initializes with config from file", %{name: name} do
    path = write_tmp_profiles!("""
    version: 1
    profiles:
      - name: "TestProfile"
        buttons: []
    """)
    System.put_env("AXON_PROFILES_PATH", path)

    start_supervised!({ConfigStore, name: name})

    assert {:ok, %LoadConfig.Config{profiles: [%{name: "TestProfile"}]}} = ConfigStore.get_config(name)
  end

  test "returns cached config without hitting disk", %{name: name} do
    path = write_tmp_profiles!("""
    version: 1
    profiles: [{name: "Initial"}]
    """)
    System.put_env("AXON_PROFILES_PATH", path)

    start_supervised!({ConfigStore, name: name})
    assert {:ok, %{profiles: [%{name: "Initial"}]}} = ConfigStore.get_config(name)

    # ファイルを削除してもキャッシュから返るはず
    File.rm!(path)
    assert {:ok, %{profiles: [%{name: "Initial"}]}} = ConfigStore.get_config(name)
  end

  test "reloads and notifies via PubSub", %{name: name} do
    path = write_tmp_profiles!("version: 1\nprofiles: [{name: 'v1', buttons: []}]")
    System.put_env("AXON_PROFILES_PATH", path)

    start_supervised!({ConfigStore, name: name})
    ConfigStore.subscribe()

    # ファイル更新
    File.write!(path, "version: 1\nprofiles: [{name: 'v2', buttons: []}]")

    # リロード実行
    # Note: ConfigStore calls LoadConfig.load() without args, 
    # so it depends on AXON_PROFILES_PATH being set correctly.
    assert :ok = ConfigStore.reload(name)

    # 通知が届くこと
    assert_receive {:config_updated, _ref}

    # 新しい値が取得できること
    assert {:ok, %{profiles: [%{name: "v2"}]}} = ConfigStore.get_config(name)
  end

  test "handles load errors gracefully", %{name: name} do
    # 不正なYAML
    path = write_tmp_profiles!("invalid: yaml: :")
    System.put_env("AXON_PROFILES_PATH", path)

    # 起動は成功する（エラーを抱えた状態）
    start_supervised!({ConfigStore, name: name})

    assert {:error, _reason} = ConfigStore.get_config(name)
  end
end
