defmodule Axon.App.KeycodesCheckTest do
  use ExUnit.Case, async: false

  alias Axon.App.Keycodes

  test "AXON-KEY-003 detects diff between generated artifact and committed file" do
    path =
      Path.join(System.tmp_dir!(), "axon-keycodes-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)

    File.write!(path, Keycodes.expected_json())
    assert :ok = Keycodes.check_file(path)

    File.write!(path, String.replace(Keycodes.expected_json(), "VK_A", "VK_B"))
    assert {:error, {:diff, _expected, _actual}} = Keycodes.check_file(path)
  end

  test "mix axon.keycodes.check exits non-zero when out of sync" do
    path =
      Path.join(
        System.tmp_dir!(),
        "axon-keycodes-diff-#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    File.write!(path, String.replace(Keycodes.expected_json(), "VK_A", "VK_B"))

    Mix.Task.reenable("axon.keycodes.check")

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Axon.Keycodes.Check.run(["--path", path])
    end
  end
end
