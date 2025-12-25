defmodule Axon.App.Execution.ShutdownPanic do
  @moduledoc false

  use GenServer

  alias Axon.App.Execution.SingleRunner

  @default_engine Axon.Adapters.MacroEngine.EnvEngine

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    engine = Keyword.get(opts, :engine, @default_engine)
    {:ok, %{engine: engine}}
  end

  @impl true
  def terminate(_reason, %{engine: engine}) do
    _ = try_engine_panic(engine)

    _ =
      try do
        SingleRunner.panic()
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end

    :ok
  end

  defp try_engine_panic(engine) do
    _ = Code.ensure_loaded(engine)

    if function_exported?(engine, :panic, 0) do
      engine.panic()
    else
      :ok
    end
  rescue
    _ -> :ok
  end
end
