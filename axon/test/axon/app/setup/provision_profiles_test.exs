defmodule Axon.App.Setup.ProvisionProfilesTest do
  # ファイルシステム操作のため
  use ExUnit.Case, async: false

  alias Axon.App.Setup.ProvisionProfiles

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "axon_provision_test_#{System.unique_integer([:positive])}")

    user_path = Path.join(tmp_dir, "profiles.yaml")

    # ProfilesPathのヘルパーをモック的に制御するのは難しいため、
    # 実際のProfilesPathが返すディレクトリ構造をシミュレートする

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir, user_path: user_path}
  end

  test "copies sample to user path if it does not exist", %{user_path: user_path} do
    sample_path = Path.join(Path.dirname(user_path), "sample.yaml")
    File.mkdir_p!(Path.dirname(sample_path))
    File.write!(sample_path, "version: 1\nprofiles: []")

    assert {:ok, ^user_path} =
             ProvisionProfiles.ensure_present(user_path: user_path, sample_path: sample_path)

    assert File.exists?(user_path)
    assert File.read!(user_path) == "version: 1\nprofiles: []"
  end

  test "does nothing if user path already exists", %{user_path: user_path} do
    File.mkdir_p!(Path.dirname(user_path))
    File.write!(user_path, "existing content")

    sample_path = Path.join(Path.dirname(user_path), "sample.yaml")
    File.write!(sample_path, "sample content")

    assert {:ok, ^user_path} =
             ProvisionProfiles.ensure_present(user_path: user_path, sample_path: sample_path)

    assert File.read!(user_path) == "existing content"
  end

  test "returns error if sample is missing", %{user_path: user_path} do
    sample_path = "/non/existent/sample.yaml"

    assert {:error, {:provision_failed, ^user_path}} =
             ProvisionProfiles.ensure_present(user_path: user_path, sample_path: sample_path)
  end
end
