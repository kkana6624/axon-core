defmodule Axon.App.Execution.MacroLog do
  @moduledoc """
  In-memory store for recent macro execution logs.
  """
  use Agent

  @max_logs 50

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def add(entry) when is_map(entry) do
    Agent.update(__MODULE__, fn logs ->
      [entry | logs] |> Enum.take(@max_logs)
    end)
  end

  def get_recent do
    Agent.get(__MODULE__, & &1)
  end

  def clear do
    Agent.update(__MODULE__, fn _ -> [] end)
  end
end
