defmodule Axon.App.ShutdownPanicTest do
  use ExUnit.Case, async: false

  alias Axon.App.Execution.SingleRunner

  setup do
    original_engine = Application.get_env(:axon, :macro_engine)

    on_exit(fn ->
      if is_nil(original_engine) do
        Application.delete_env(:axon, :macro_engine)
      else
        Application.put_env(:axon, :macro_engine, original_engine)
      end

      _ =
        try do
          SingleRunner.reset()
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end
    end)

    :ok
  end

  test "AXON-EXEC-005 panic is called on shutdown (smoke)" do
    Application.put_env(:axon, :macro_engine, panic_notify_pid: self())

    pid = Process.whereis(Axon.App.Execution.ShutdownPanic)
    assert is_pid(pid)

    :ok = :sys.terminate(pid, :shutdown)

    assert_receive {:engine_panic_called, _from_pid}, 1_000
  end
end
