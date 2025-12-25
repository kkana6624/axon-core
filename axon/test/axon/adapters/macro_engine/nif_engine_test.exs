defmodule Axon.Adapters.MacroEngine.NifEngineTest do
  use ExUnit.Case, async: true

  alias Axon.Adapters.MacroEngine.NifEngine

  test "available?/0 returns a boolean and never crashes" do
    assert is_boolean(NifEngine.available?())
  end

  test "key_tap/1 returns an engine error tuple when unavailable" do
    case :os.type() do
      {:unix, _} ->
        assert {:error, :engine_unavailable, "engine unavailable"} = NifEngine.key_tap("VK_A")

      {:win32, _} ->
        # On Windows this is currently a stub.
        assert {:error, :engine_failure, "engine failure"} = NifEngine.key_tap("VK_A")
    end
  end
end
