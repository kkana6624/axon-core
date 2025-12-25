defmodule Axon.App.ExecuteMacro do
  @moduledoc false

  require Logger

  alias Axon.App.Execution.SingleRunner
  alias Axon.App.Macro.TapMacro
  alias Axon.Adapters.MacroEngine.EnvEngine

  @type ack_payload :: TapMacro.ack_payload()

  @spec tap_macro(map(), keyword()) :: {:accepted, ack_payload()} | {:rejected, ack_payload()}
  def tap_macro(payload, opts \\ [])

  def tap_macro(payload, opts) when is_map(payload) do
    reply_to = Keyword.get(opts, :reply_to, self())
    owner_pid = Keyword.get(opts, :owner_pid, self())

    tap_opts = Keyword.take(opts, [:config_loader, :engine, :clock])

    case TapMacro.preflight(payload, tap_opts) do
      {:rejected, ack} ->
        {:rejected, ack}

      {:accepted, ack, exec_spec} ->
        request_id = Map.get(payload, "request_id")

        profile = Map.fetch!(exec_spec, :profile)
        button_id = Map.fetch!(exec_spec, :button_id)

        case SingleRunner.start_execution(owner_pid, request_id, fn ->
               started_ms = System.monotonic_time(:millisecond)

               Logger.info(
                 "macro_started profile=#{profile} button_id=#{button_id} request_id=#{request_id}"
               )

               result_payload =
                 try do
                   execute_with_timeout(exec_spec, request_id)
                 rescue
                   _ ->
                     %{
                       "status" => "error",
                       "error_code" => "E_INTERNAL",
                       "message" => "internal error",
                       "request_id" => request_id
                     }
                 catch
                   _, _ ->
                     %{
                       "status" => "error",
                       "error_code" => "E_INTERNAL",
                       "message" => "internal error",
                       "request_id" => request_id
                     }
                 end

               duration_ms = System.monotonic_time(:millisecond) - started_ms
               result = Map.get(result_payload, "status", "unknown")

               Logger.info(
                 "macro_finished profile=#{profile} button_id=#{button_id} request_id=#{request_id} result=#{result} duration_ms=#{duration_ms}"
               )

               send(reply_to, {:emit_macro_result, result_payload})
             end) do
          :busy ->
            {:rejected, %{"accepted" => false, "reason" => "busy", "request_id" => request_id}}

          :rate_limited ->
            {:rejected, %{"accepted" => false, "reason" => "busy", "request_id" => request_id}}

          :panic ->
            {:rejected, %{"accepted" => false, "reason" => "busy", "request_id" => request_id}}

          :ok ->
            {:accepted, ack}
        end
    end
  end

  def tap_macro(_payload, _opts) do
    {:rejected, %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}}
  end

  @spec panic(map(), keyword()) :: {:accepted, ack_payload()} | {:rejected, ack_payload()}
  def panic(payload, opts \\ [])

  def panic(payload, opts) when is_map(payload) do
    reply_to = Keyword.get(opts, :reply_to, self())
    engine = Keyword.get(opts, :engine, EnvEngine)

    panic_request_id = Map.get(payload, "request_id")

    if is_binary(panic_request_id) and panic_request_id != "" do
      _ = try_engine_panic(engine)

      interrupted_request_id =
        case SingleRunner.panic() do
          {:interrupted, request_id} when is_binary(request_id) and request_id != "" -> request_id
          _ -> panic_request_id
        end

      send(reply_to, {
        :emit_macro_result,
        %{"status" => "panic", "request_id" => interrupted_request_id}
      })

      {:accepted, %{"accepted" => true, "request_id" => panic_request_id}}
    else
      {:rejected, %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}}
    end
  end

  def panic(_payload, _opts) do
    {:rejected, %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}}
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

  defp execute_with_timeout(exec_spec, request_id) do
    timeout_ms = Application.get_env(:axon, :macro_result_timeout_ms, 3_000)

    if is_integer(timeout_ms) and timeout_ms > 0 do
      task = Task.async(fn -> TapMacro.execute(exec_spec) end)

      try do
        Task.await(task, timeout_ms)
      catch
        :exit, {:timeout, _} ->
          _ = Task.shutdown(task, :brutal_kill)

          %{
            "status" => "error",
            "error_code" => "E_TIMEOUT",
            "message" => "timeout",
            "request_id" => request_id
          }
      end
    else
      TapMacro.execute(exec_spec)
    end
  end
end
