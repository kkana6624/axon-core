defmodule AxonWeb.MacroLiveTest do
  use AxonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Axon.App.Execution.SingleRunner

  defmodule EngineNoStepApi do
    def available?, do: true
  end

  setup do
    original = System.get_env("AXON_PROFILES_PATH")
    original_engine = Application.get_env(:axon, :macro_engine)
    original_engine_module = Application.get_env(:axon, :macro_engine_module)
    original_interval = Application.get_env(:axon, :tap_macro_min_interval_ms)

    on_exit(fn ->
      if is_nil(original) do
        System.delete_env("AXON_PROFILES_PATH")
      else
        System.put_env("AXON_PROFILES_PATH", original)
      end

      if is_nil(original_engine) do
        Application.delete_env(:axon, :macro_engine)
      else
        Application.put_env(:axon, :macro_engine, original_engine)
      end

      if is_nil(original_engine_module) do
        Application.delete_env(:axon, :macro_engine_module)
      else
        Application.put_env(:axon, :macro_engine_module, original_engine_module)
      end

      if is_nil(original_interval) do
        Application.delete_env(:axon, :tap_macro_min_interval_ms)
      else
        Application.put_env(:axon, :tap_macro_min_interval_ms, original_interval)
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

  defp write_tmp_profiles!(contents) when is_binary(contents) do
    dir = System.tmp_dir!()
    path = Path.join(dir, "axon_profiles_#{System.unique_integer([:positive])}.yaml")
    File.write!(path, contents)
    path
  end

  defp configure_ok! do
    path =
      write_tmp_profiles!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "save_all"
              sequence:
                - action: "tap"
                  key: "VK_A"
      """)

    System.put_env("AXON_PROFILES_PATH", path)
    :ok
  end

  defp assert_push_event_exact(
         view,
         event,
         expected_payload,
         timeout \\ Application.fetch_env!(:ex_unit, :assert_receive_timeout)
       )
       when is_binary(event) and is_map(expected_payload) do
    %{proxy: {ref, _topic, _}} = view

    assert_receive {^ref, {:push_event, ^event, payload}}, timeout
    assert payload == expected_payload
  end

  test "AXON-LV-001 tap_macro returns macro_ack accepted", %{conn: conn} do
    configure_ok!()
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000001"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-000000000001"
    })
  end

  test "AXON-LV-002 invalid payload is rejected", %{conn: conn} do
    configure_ok!()
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{"profile" => "Development"})

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "invalid_request",
      "request_id" => nil
    })
  end

  test "AXON-LV-003 not configured is rejected", %{conn: conn} do
    System.delete_env("AXON_PROFILES_PATH")

    {:ok, view, _html} = live(conn, ~p"/__test__/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000003"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "not_configured",
      "request_id" => "00000000-0000-0000-0000-000000000003"
    })
  end

  test "AXON-LV-004 macro not found is rejected", %{conn: conn} do
    configure_ok!()
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "does_not_exist",
      "request_id" => "00000000-0000-0000-0000-000000000004"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "not_found",
      "request_id" => "00000000-0000-0000-0000-000000000004"
    })
  end

  test "AXON-LV-005 engine unavailable is rejected", %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: false)
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000005"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "engine_unavailable",
      "request_id" => "00000000-0000-0000-0000-000000000005"
    })
  end

  test "AXON-LV-006 macro_result ok is emitted asynchronously", %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: true, result: :ok)
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000006"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-000000000006"
    })

    assert_push_event_exact(view, "macro_result", %{
      "status" => "ok",
      "request_id" => "00000000-0000-0000-0000-000000000006"
    })
  end

  test "AXON-LV-007 macro_result error is emitted with error_code and message", %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: true, result: :error)
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000007"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-000000000007"
    })

    assert_push_event_exact(view, "macro_result", %{
      "status" => "error",
      "error_code" => "E_ENGINE_FAILURE",
      "message" => "engine failure",
      "request_id" => "00000000-0000-0000-0000-000000000007"
    })
  end

  test "AXON-LV-008 engine step API missing emits E_ENGINE_UNAVAILABLE", %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine_module, EngineNoStepApi)
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000008"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-000000000008"
    })

    assert_push_event_exact(view, "macro_result", %{
      "status" => "error",
      "error_code" => "E_ENGINE_UNAVAILABLE",
      "message" => "engine unavailable",
      "request_id" => "00000000-0000-0000-0000-000000000008"
    })
  end

  test "AXON-EXEC-001 second tap_macro is rejected as busy while first is running", %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: true, result: :ok, delay_ms: 200)

    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000A001"
    })

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000A002"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000A001"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "busy",
      "request_id" => "00000000-0000-0000-0000-00000000A002"
    })

    assert_push_event_exact(
      view,
      "macro_result",
      %{
        "status" => "ok",
        "request_id" => "00000000-0000-0000-0000-00000000A001"
      },
      1_000
    )
  end

  test "AXON-EXEC-003 panic interrupts running macro and emits macro_result panic immediately", %{
    conn: conn
  } do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: true, result: :ok, delay_ms: 1_000)

    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000B001"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000B001"
    })

    render_hook(view, "panic", %{
      "request_id" => "00000000-0000-0000-0000-00000000P001"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000P001"
    })

    assert_push_event_exact(
      view,
      "macro_result",
      %{
        "status" => "panic",
        "request_id" => "00000000-0000-0000-0000-00000000B001"
      },
      300
    )

    %{proxy: {ref, _topic, _}} = view

    refute_receive {^ref,
                    {:push_event, "macro_result",
                     %{"status" => "ok", "request_id" => "00000000-0000-0000-0000-00000000B001"}}},
                   500
  end

  test "AXON-EXEC-004 after panic, next macro request is rejected until recovery (MVP: reject)",
       %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: true, result: :ok, delay_ms: 1_000)

    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000C001"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000C001"
    })

    render_hook(view, "panic", %{
      "request_id" => "00000000-0000-0000-0000-00000000P002"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000P002"
    })

    assert_push_event_exact(
      view,
      "macro_result",
      %{
        "status" => "panic",
        "request_id" => "00000000-0000-0000-0000-00000000C001"
      },
      300
    )

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000C002"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "busy",
      "request_id" => "00000000-0000-0000-0000-00000000C002"
    })
  end

  test "AXON-EXEC-002 repeat tap_macro within min interval is rejected (busy) even after completion",
       %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :tap_macro_min_interval_ms, 1_000)
    Application.put_env(:axon, :macro_engine, available: true, result: :ok, delay_ms: 0)

    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000D001"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000D001"
    })

    assert_push_event_exact(
      view,
      "macro_result",
      %{
        "status" => "ok",
        "request_id" => "00000000-0000-0000-0000-00000000D001"
      },
      1_000
    )

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000D002"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "busy",
      "request_id" => "00000000-0000-0000-0000-00000000D002"
    })
  end

  test "AXON-WS-001 ack is immediate and timeout result includes request_id", %{conn: conn} do
    configure_ok!()

    original_timeout = Application.get_env(:axon, :macro_result_timeout_ms)

    on_exit(fn ->
      if is_nil(original_timeout) do
        Application.delete_env(:axon, :macro_result_timeout_ms)
      else
        Application.put_env(:axon, :macro_result_timeout_ms, original_timeout)
      end
    end)

    Application.put_env(:axon, :tap_macro_min_interval_ms, 0)
    Application.put_env(:axon, :macro_result_timeout_ms, 50)
    Application.put_env(:axon, :macro_engine, available: true, result: :ok, delay_ms: 200)

    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000WS01"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000WS01"
    })

    assert_push_event_exact(
      view,
      "macro_result",
      %{
        "status" => "error",
        "error_code" => "E_TIMEOUT",
        "message" => "timeout",
        "request_id" => "00000000-0000-0000-0000-00000000WS01"
      },
      1_000
    )
  end

  test "AXON-WS-002 timeout threshold is configurable", %{conn: conn} do
    configure_ok!()

    original_timeout = Application.get_env(:axon, :macro_result_timeout_ms)

    on_exit(fn ->
      if is_nil(original_timeout) do
        Application.delete_env(:axon, :macro_result_timeout_ms)
      else
        Application.put_env(:axon, :macro_result_timeout_ms, original_timeout)
      end
    end)

    Application.put_env(:axon, :tap_macro_min_interval_ms, 0)
    Application.put_env(:axon, :macro_engine, available: true, result: :ok, delay_ms: 80)

    {:ok, view, _html} = live(conn, ~p"/macro")

    Application.put_env(:axon, :macro_result_timeout_ms, 20)

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000WS02A"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000WS02A"
    })

    assert_push_event_exact(
      view,
      "macro_result",
      %{
        "status" => "error",
        "error_code" => "E_TIMEOUT",
        "message" => "timeout",
        "request_id" => "00000000-0000-0000-0000-00000000WS02A"
      },
      1_000
    )

    Application.put_env(:axon, :macro_result_timeout_ms, 200)

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-00000000WS02B"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-00000000WS02B"
    })

    assert_push_event_exact(
      view,
      "macro_result",
      %{
        "status" => "ok",
        "request_id" => "00000000-0000-0000-0000-00000000WS02B"
      },
      1_000
    )
  end

  test "AXON-DISC-001 server_info is pushed on mount", %{conn: conn} do
    configure_ok!()
    {:ok, view, _html} = live(conn, ~p"/macro")

    assert_push_event_exact(view, "server_info", %{
      "version" => "0.1.0",
      "capabilities" => ["tap_macro", "panic", "vibrate"]
    })
  end
end
