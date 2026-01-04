defmodule Axon.Adapters.MacroEngine.NifEngineContractTest do
  use ExUnit.Case, async: true

  alias Axon.Adapters.MacroEngine.NifEngine

  @tag :windows
  test "key_tap handles standard keys" do
    if :os.type() == {:win32, :nt} do
      assert :ok = NifEngine.key_tap("VK_A")
      assert :ok = NifEngine.key_tap("VK_SPACE")
    end
  end

  @tag :windows
  test "key_tap handles VK_ENTER mapping" do
    if :os.type() == {:win32, :nt} do
      # Spec says VK_ENTER should work
      assert :ok = NifEngine.key_tap("VK_ENTER")
    end
  end

  test "key_tap returns config_invalid for unknown keys" do
    assert {:error, :config_invalid, _} = NifEngine.key_tap("UNKNOWN_KEY")
  end

  test "execute_sequence maps actions correctly" do
    # This test checks the preparation logic (pre-NIF)
    # We use a dummy sequence to check if it fails early on invalid keys
    sequence = [
      %{"action" => "down", "key" => "VK_A"},
      %{"action" => "wait", "value" => 10},
      %{"action" => "up", "key" => "VK_A"}
    ]

    if :os.type() == {:win32, :nt} do
      assert :ok = NifEngine.execute_sequence(sequence)
    end
  end

  test "execute_sequence fails for sequence with unknown keys" do
    sequence = [
      %{"action" => "tap", "key" => "INVALID"}
    ]

    assert {:error, :config_invalid, _} = NifEngine.execute_sequence(sequence)
  end

  @tag :windows
  test "all keys from Rust are supported in NifEngine" do
    if :os.type() == {:win32, :nt} do
      # Get all key names that Rust claims to support
      rust_keys = Axon.App.Keycodes.keys()
      assert length(rust_keys) > 0

      # Try to map each one. We don't call key_tap (to avoid side effects), 
      # but we test the private mapping via execute_sequence with a dummy action.
      for key_name <- rust_keys do
        # If it's a known key, preparing should not fail with :invalid_key
        sequence = [%{"action" => "tap", "key" => key_name}]

        # We check if NifEngine can prepare it
        res = NifEngine.execute_sequence(sequence)

        # It should either be :ok or an engine error, but NOT config_invalid (mapping error)
        case res do
          {:error, :config_invalid, msg} ->
            flunk("Key '#{key_name}' is not mapped in NifEngine: #{msg}")

          _ ->
            :ok
        end
      end
    end
  end
end
