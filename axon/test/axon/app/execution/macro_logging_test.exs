defmodule Axon.App.Execution.MacroLoggingTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Axon.App.Execution.MacroCoordinator
  alias Axon.App.Execution.SingleRunner

  defmodule FakeConfigLoader do
    def load do
      {:ok,
       %Axon.App.LoadConfig.Config{
         version: 1,
         profiles: [
           %{
             raw: %{
               "name" => "Dev",
               "buttons" => [
                 %{
                   "id" => "b1",
                   "sequence" => [%{"action" => "tap", "key" => "VK_A"}]
                 }
               ]
             }
           }
         ]
       }}
    end
  end

  defmodule FakeEngineOk do
    def available?, do: true
    def key_tap(_key), do: :ok
  end

  defmodule FakeEngineError do
    def available?, do: true
    def key_tap(_key), do: {:error, :engine_failure, "engine failure"}
  end

  setup do
    original_logger_level = Logger.level()
    Logger.configure(level: :info)

    original_min_interval = Application.get_env(:axon, :tap_macro_min_interval_ms)
    Application.put_env(:axon, :tap_macro_min_interval_ms, 0)

    _ =
      try do
        SingleRunner.reset()
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end

    on_exit(fn ->
      Logger.configure(level: original_logger_level)

      if is_nil(original_min_interval) do
        Application.delete_env(:axon, :tap_macro_min_interval_ms)
      else
        Application.put_env(:axon, :tap_macro_min_interval_ms, original_min_interval)
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

  test "AXON-LOG-001..002 emits started/finished logs (ok)" do
    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r1"}

    log =
      capture_log(fn ->
        assert {:accepted, %{"accepted" => true, "request_id" => "r1"}} =
                 MacroCoordinator.tap_macro(payload,
                   reply_to: self(),
                   owner_pid: self(),
                   config_loader: FakeConfigLoader,
                   engine: FakeEngineOk
                 )

        assert_receive {:emit_macro_result, %{"status" => "ok", "request_id" => "r1"}}, 1_000
      end)

    assert log =~ "macro_started"
    assert log =~ "profile=Dev"
    assert log =~ "button_id=b1"
    assert log =~ "request_id=r1"

    assert log =~ "macro_finished"
    assert log =~ "result=ok"
    assert Regex.match?(~r/duration_ms=\d+/, log)
  end

  test "AXON-LOG-003 emits finished log on error (result=error)" do
    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r2"}

    log =
      capture_log(fn ->
        assert {:accepted, %{"accepted" => true, "request_id" => "r2"}} =
                 MacroCoordinator.tap_macro(payload,
                   reply_to: self(),
                   owner_pid: self(),
                   config_loader: FakeConfigLoader,
                   engine: FakeEngineError
                 )

        assert_receive {:emit_macro_result,
                        %{
                          "status" => "error",
                          "error_code" => "E_ENGINE_FAILURE",
                          "message" => "engine failure",
                          "request_id" => "r2"
                        }}, 1_000
      end)

    assert log =~ "macro_finished"
    assert log =~ "profile=Dev"
    assert log =~ "button_id=b1"
    assert log =~ "request_id=r2"
    assert log =~ "result=error"
    assert Regex.match?(~r/duration_ms=\d+/, log)
  end
end
