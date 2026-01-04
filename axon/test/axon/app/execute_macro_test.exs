defmodule Axon.App.ExecuteMacroTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Axon.App.ExecuteMacro
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

  defmodule SlowEngineOk do
    def available?, do: true

    def key_tap(_key) do
      Process.sleep(300)
      :ok
    end
  end

  defmodule EngineOk do
    def available?, do: true
    def key_tap(_key), do: :ok
  end

  defmodule EngineError do
    def available?, do: true
    def key_tap(_key), do: {:error, :engine_failure, "engine failure"}
  end

  defmodule EngineRaises do
    def available?, do: true

    def key_tap(_key) do
      raise "boom"
    end
  end

  defmodule EngineExits do
    def available?, do: true

    def key_tap(_key) do
      exit(:boom)
    end
  end

  defmodule Recorder do
    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def push(event) when is_atom(event) do
      Agent.update(__MODULE__, fn events -> events ++ [event] end)
    end

    def events do
      Agent.get(__MODULE__, & &1)
    end
  end

  defmodule FakeClock do
    def sleep(ms) when is_integer(ms) and ms >= 0 do
      Recorder.push(String.to_atom("wait_#{ms}"))
      :ok
    end
  end

  defmodule ConfigWithWaits do
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
                   "sequence" => [
                     %{"action" => "wait", "value" => 0},
                     %{"action" => "wait", "value" => 10},
                     %{"action" => "tap", "key" => "VK_A"}
                   ]
                 }
               ]
             }
           }
         ]
       }}
    end
  end

  defmodule EngineOkRecorded do
    def available?, do: true

    def key_tap(_key) do
      Recorder.push(:engine_tap)
      :ok
    end
  end

  defmodule EngineNoStepApi do
    def available?, do: true
  end

  defmodule ConfigWithTap do
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

  defmodule ConfigWithInvalidAction do
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
                   "sequence" => [%{"action" => "nope"}]
                 }
               ]
             }
           }
         ]
       }}
    end
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

  test "AXON-WAIT exec uses injected clock and preserves wait order" do
    {:ok, _pid} = Recorder.start_link()

    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r_wait"}

    assert {:accepted, %{"accepted" => true, "request_id" => "r_wait"}} =
             ExecuteMacro.tap_macro(payload,
               reply_to: self(),
               owner_pid: self(),
               config_loader: ConfigWithWaits,
               engine: EngineOkRecorded,
               clock: FakeClock
             )

    assert_receive {:emit_macro_result, %{"status" => "ok", "request_id" => "r_wait"}}, 1_000

    assert Recorder.events() == [:wait_0, :wait_10, :engine_tap]
  end

  test "execution returns E_ENGINE_UNAVAILABLE when engine lacks step API" do
    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r_unavail"}

    assert {:accepted, %{"accepted" => true, "request_id" => "r_unavail"}} =
             ExecuteMacro.tap_macro(payload,
               reply_to: self(),
               owner_pid: self(),
               config_loader: ConfigWithTap,
               engine: EngineNoStepApi
             )

    assert_receive {:emit_macro_result,
                    %{
                      "status" => "error",
                      "error_code" => "E_ENGINE_UNAVAILABLE",
                      "message" => "engine unavailable",
                      "request_id" => "r_unavail"
                    }},
                   1_000
  end

  test "execution returns E_CONFIG_INVALID on invalid action step" do
    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r_cfg"}

    assert {:accepted, %{"accepted" => true, "request_id" => "r_cfg"}} =
             ExecuteMacro.tap_macro(payload,
               reply_to: self(),
               owner_pid: self(),
               config_loader: ConfigWithInvalidAction,
               engine: EngineOk
             )

    assert_receive {:emit_macro_result,
                    %{
                      "status" => "error",
                      "error_code" => "E_CONFIG_INVALID",
                      "message" => "invalid action",
                      "request_id" => "r_cfg"
                    }},
                   1_000
  end

  test "execution returns E_INTERNAL when engine step raises" do
    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r_internal_raise"}

    assert {:accepted, %{"accepted" => true, "request_id" => "r_internal_raise"}} =
             ExecuteMacro.tap_macro(payload,
               reply_to: self(),
               owner_pid: self(),
               config_loader: ConfigWithTap,
               engine: EngineRaises
             )

    assert_receive {:emit_macro_result,
                    %{
                      "status" => "error",
                      "error_code" => "E_INTERNAL",
                      "message" => "internal error",
                      "request_id" => "r_internal_raise"
                    }},
                   1_000
  end

  test "execution returns E_INTERNAL when engine step exits" do
    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r_internal_exit"}

    assert {:accepted, %{"accepted" => true, "request_id" => "r_internal_exit"}} =
             ExecuteMacro.tap_macro(payload,
               reply_to: self(),
               owner_pid: self(),
               config_loader: ConfigWithTap,
               engine: EngineExits
             )

    assert_receive {:emit_macro_result,
                    %{
                      "status" => "error",
                      "error_code" => "E_INTERNAL",
                      "message" => "internal error",
                      "request_id" => "r_internal_exit"
                    }},
                   1_000
  end

  test "AXON-EXEC-001 second request is busy while executing" do
    payload1 = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r1"}
    payload2 = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r2"}

    assert {:accepted, %{"accepted" => true, "request_id" => "r1"}} =
             ExecuteMacro.tap_macro(payload1,
               reply_to: self(),
               owner_pid: self(),
               config_loader: FakeConfigLoader,
               engine: SlowEngineOk
             )

    assert {:rejected, %{"accepted" => false, "reason" => "busy", "request_id" => "r2"}} =
             ExecuteMacro.tap_macro(payload2,
               reply_to: self(),
               owner_pid: self(),
               config_loader: FakeConfigLoader,
               engine: SlowEngineOk
             )

    assert_receive {:emit_macro_result, %{"status" => "ok", "request_id" => "r1"}}, 2_000
  end

  test "AXON-EXEC-003 panic interrupts running macro" do
    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r1"}

    assert {:accepted, %{"accepted" => true, "request_id" => "r1"}} =
             ExecuteMacro.tap_macro(payload,
               reply_to: self(),
               owner_pid: self(),
               config_loader: FakeConfigLoader,
               engine: SlowEngineOk
             )

    assert {:accepted, %{"accepted" => true, "request_id" => "p1"}} =
             ExecuteMacro.panic(%{"request_id" => "p1"}, reply_to: self())

    assert_receive {:emit_macro_result, %{"status" => "panic", "request_id" => "r1"}}, 1_000
  end

  test "AXON-LOG-001..003 emits started/finished logs" do
    ok_payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r_ok"}
    err_payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r_err"}

    ok_log =
      capture_log(fn ->
        assert {:accepted, %{"accepted" => true, "request_id" => "r_ok"}} =
                 ExecuteMacro.tap_macro(ok_payload,
                   reply_to: self(),
                   owner_pid: self(),
                   config_loader: FakeConfigLoader,
                   engine: EngineOk
                 )

        assert_receive {:emit_macro_result, %{"status" => "ok", "request_id" => "r_ok"}}, 1_000
      end)

    assert ok_log =~ "macro_started"
    assert ok_log =~ "profile=Dev"
    assert ok_log =~ "button_id=b1"
    assert ok_log =~ "request_id=r_ok"
    assert ok_log =~ "macro_finished"
    assert ok_log =~ "result=ok"
    assert Regex.match?(~r/duration_ms=\d+/, ok_log)

    err_log =
      capture_log(fn ->
        assert {:accepted, %{"accepted" => true, "request_id" => "r_err"}} =
                 ExecuteMacro.tap_macro(err_payload,
                   reply_to: self(),
                   owner_pid: self(),
                   config_loader: FakeConfigLoader,
                   engine: EngineError
                 )

        assert_receive {:emit_macro_result,
                        %{
                          "status" => "error",
                          "error_code" => "E_ENGINE_FAILURE",
                          "message" => "engine failure",
                          "request_id" => "r_err"
                        }},
                       1_000
      end)

    assert err_log =~ "macro_finished"
    assert err_log =~ "result=error"
    assert Regex.match?(~r/duration_ms=\d+/, err_log)
  end

  test "AXON-EXEC-004 panic_reset allows recovery from panic state" do
    # 1. Enter panic state
    ExecuteMacro.panic(%{"request_id" => "p1"}, reply_to: self())
    assert_receive {:emit_macro_result, %{"status" => "panic"}}

    # 2. Macro should be rejected
    payload = %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r_rejected"}

    assert {:rejected, %{"accepted" => false, "reason" => "busy"}} =
             ExecuteMacro.tap_macro(payload,
               reply_to: self(),
               owner_pid: self(),
               config_loader: FakeConfigLoader,
               engine: EngineOk
             )

    # 3. Reset panic
    assert :ok = ExecuteMacro.panic_reset()

    # 4. Macro should now be accepted
    assert {:accepted, %{"accepted" => true, "request_id" => "r_accepted"}} =
             ExecuteMacro.tap_macro(%{payload | "request_id" => "r_accepted"},
               reply_to: self(),
               owner_pid: self(),
               config_loader: FakeConfigLoader,
               engine: EngineOk
             )

    assert_receive {:emit_macro_result, %{"status" => "ok"}}, 1_000
  end
end
