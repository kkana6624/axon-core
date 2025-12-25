defmodule Axon.App.Execution.MacroCoordinator do
  @moduledoc false

  alias Axon.App.ExecuteMacro

  alias Axon.App.Macro.TapMacro

  @type ack_payload :: TapMacro.ack_payload()

  @spec tap_macro(map(), keyword()) :: {:accepted, ack_payload()} | {:rejected, ack_payload()}
  def tap_macro(payload, opts \\ [])

  def tap_macro(payload, opts) when is_map(payload), do: ExecuteMacro.tap_macro(payload, opts)
  def tap_macro(_payload, _opts), do: ExecuteMacro.tap_macro(%{}, [])

  @spec panic(map(), keyword()) :: {:accepted, ack_payload()} | {:rejected, ack_payload()}
  def panic(payload, opts \\ [])

  def panic(payload, opts) when is_map(payload), do: ExecuteMacro.panic(payload, opts)
  def panic(_payload, _opts), do: ExecuteMacro.panic(%{}, [])
end
