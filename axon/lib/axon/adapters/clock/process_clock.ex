defmodule Axon.Adapters.Clock.ProcessClock do
  @moduledoc false

  @spec sleep(non_neg_integer()) :: :ok
  def sleep(ms) when is_integer(ms) and ms >= 0 do
    Process.sleep(ms)
    :ok
  end
end
