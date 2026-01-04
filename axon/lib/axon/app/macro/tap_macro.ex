defmodule Axon.App.Macro.TapMacro do
  @moduledoc false

  alias Axon.App.LoadConfig

  @type ack_payload :: %{
          required(String.t()) => any()
        }

  @type result_payload :: %{
          required(String.t()) => any()
        }

  @type outcome ::
          {:rejected, ack_payload()}
          | {:accepted, ack_payload(), result_payload()}

  @type exec_spec :: %{
          required(:profile) => String.t(),
          required(:button_id) => String.t(),
          required(:request_id) => String.t(),
          required(:engine) => module(),
          required(:clock) => module(),
          required(:sequence) => list(map())
        }

  def call(payload, opts \\ [])

  def call(payload, opts) when is_map(payload) do
    case preflight(payload, opts) do
      {:rejected, ack} ->
        {:rejected, ack}

      {:accepted, ack, exec_spec} ->
        {:accepted, ack, execute(exec_spec)}
    end
  end

  def call(_payload, _opts) do
    {:rejected, %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}}
  end

  defp config_provider, do: Application.get_env(:axon, :config_provider)

  @spec preflight(map(), keyword()) ::
          {:rejected, ack_payload()} | {:accepted, ack_payload(), exec_spec()}
  def preflight(payload, opts \\ [])

  def preflight(payload, opts) when is_map(payload) do
    # Support both config_provider (new) and config_loader (legacy)
    provider =
      Keyword.get(opts, :config_provider) || Keyword.get(opts, :config_loader) ||
        config_provider()

    engine =
      Keyword.get(
        opts,
        :engine,
        Application.get_env(:axon, :macro_engine_module, Axon.Adapters.MacroEngine.EnvEngine)
      )

    clock = Keyword.get(opts, :clock, Axon.Adapters.Clock.ProcessClock)

    request_id = Map.get(payload, "request_id")

    case validate_payload(payload) do
      :ok ->
        profile = Map.get(payload, "profile")
        button_id = Map.get(payload, "button_id")

        case fetch_config(provider) do
          {:ok, config} ->
            with :ok <- ensure_macro_exists(config, profile, button_id),
                 :ok <- ensure_engine_available(engine) do
              ack = %{"accepted" => true, "request_id" => request_id}

              sequence = fetch_sequence(config, profile, button_id)

              exec_spec = %{
                profile: profile,
                button_id: button_id,
                request_id: request_id,
                engine: engine,
                clock: clock,
                sequence: sequence
              }

              {:accepted, ack, exec_spec}
            else
              {:error, :not_found} ->
                {:rejected,
                 %{"accepted" => false, "reason" => "not_found", "request_id" => request_id}}

              {:error, :engine_unavailable} ->
                {:rejected,
                 %{
                   "accepted" => false,
                   "reason" => "engine_unavailable",
                   "request_id" => request_id
                 }}
            end

          {:error, _reason} ->
            {:rejected,
             %{"accepted" => false, "reason" => "not_configured", "request_id" => request_id}}
        end

      {:error, reason} ->
        {:rejected, %{"accepted" => false, "reason" => reason, "request_id" => request_id}}
    end
  end

  def preflight(_payload, _opts) do
    {:rejected, %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}}
  end

  @spec execute(exec_spec()) :: result_payload()
  def execute(
        %{profile: profile, button_id: button_id, request_id: request_id, engine: engine} =
          exec_spec
      )
      when is_binary(profile) and is_binary(button_id) and is_binary(request_id) do
    sequence = Map.get(exec_spec, :sequence, [])
    clock = Map.get(exec_spec, :clock)

    case execute_sequence(sequence, engine, clock, profile, button_id, request_id) do
      :ok ->
        %{"status" => "ok", "request_id" => request_id}

      {:error, :engine_failure, message} ->
        %{
          "status" => "error",
          "error_code" => "E_ENGINE_FAILURE",
          "message" => message,
          "request_id" => request_id
        }

      {:error, :engine_unavailable, message} ->
        %{
          "status" => "error",
          "error_code" => "E_ENGINE_UNAVAILABLE",
          "message" => message,
          "request_id" => request_id
        }

      {:error, :config_invalid, message} ->
        %{
          "status" => "error",
          "error_code" => "E_CONFIG_INVALID",
          "message" => message,
          "request_id" => request_id
        }

      {:error, :internal, message} ->
        %{
          "status" => "error",
          "error_code" => "E_INTERNAL",
          "message" => message,
          "request_id" => request_id
        }
    end
  end

  defp execute_sequence(sequence, engine, clock, profile, button_id, request_id)
       when is_list(sequence) and is_atom(engine) do
    _ = Code.ensure_loaded(engine)

    if function_exported?(engine, :execute_sequence, 1) do
      # Optimization: Execute entire sequence at once in the engine (Rust)
      case engine.execute_sequence(sequence) do
        :ok -> :ok
        {:error, :engine_failure, message} -> {:error, :engine_failure, message}
        {:error, :engine_unavailable, message} -> {:error, :engine_unavailable, message}
        {:error, :config_invalid, message} -> {:error, :config_invalid, message}
        _ -> {:error, :engine_failure, "engine failure"}
      end
    else
      # Fallback: Execute step-by-step in Elixir
      Enum.reduce_while(sequence, :ok, fn step, :ok ->
        case execute_step(step, engine, clock, profile, button_id, request_id) do
          :ok -> {:cont, :ok}
          {:error, _, _} = err -> {:halt, err}
        end
      end)
    end
  rescue
    _ -> {:error, :internal, "internal error"}
  catch
    :exit, _ -> {:error, :internal, "internal error"}
    _, _ -> {:error, :internal, "internal error"}
  end

  defp execute_sequence(_sequence, _engine, _clock, _profile, _button_id, _request_id), do: :ok

  defp execute_step(
         %{"action" => "wait", "value" => value},
         _engine,
         clock,
         _profile,
         _button_id,
         _request_id
       )
       when is_integer(value) and value >= 0 do
    _ = Code.ensure_loaded(clock)

    if is_atom(clock) and function_exported?(clock, :sleep, 1) do
      _ = clock.sleep(value)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp execute_step(
         %{"action" => action, "key" => key},
         engine,
         _clock,
         profile,
         button_id,
         request_id
       )
       when action in ["down", "up", "tap"] and is_binary(key) and key != "" do
    _ = Code.ensure_loaded(engine)

    cond do
      action == "down" and function_exported?(engine, :key_down, 1) ->
        safe_engine_step(fn -> engine.key_down(key) end) |> normalize_engine_result()

      action == "up" and function_exported?(engine, :key_up, 1) ->
        safe_engine_step(fn -> engine.key_up(key) end) |> normalize_engine_result()

      action == "tap" and function_exported?(engine, :key_tap, 1) ->
        safe_engine_step(fn -> engine.key_tap(key) end) |> normalize_engine_result()

      function_exported?(engine, :run, 3) ->
        # Backward-compatible fallback (pre-sequence engine)
        safe_engine_step(fn -> engine.run(profile, button_id, request_id) end)
        |> normalize_engine_result()

      true ->
        {:error, :engine_unavailable, "engine unavailable"}
    end
  rescue
    UndefinedFunctionError ->
      {:error, :engine_unavailable, "engine unavailable"}
  end

  defp execute_step(%{"action" => "panic"}, engine, _clock, _profile, _button_id, _request_id) do
    _ = Code.ensure_loaded(engine)

    if function_exported?(engine, :panic, 0) do
      _ = engine.panic()
    end

    :ok
  rescue
    _ -> :ok
  end

  defp execute_step(%{"action" => other}, _engine, _clock, _profile, _button_id, _request_id)
       when is_binary(other) do
    {:error, :config_invalid, "invalid action"}
  end

  defp execute_step(_other, _engine, _clock, _profile, _button_id, _request_id) do
    {:error, :config_invalid, "invalid step"}
  end

  defp safe_engine_step(fun) when is_function(fun, 0) do
    fun.()
  rescue
    _ -> {:error, :internal, "internal error"}
  catch
    :exit, _ -> {:error, :internal, "internal error"}
    _, _ -> {:error, :internal, "internal error"}
  end

  defp normalize_engine_result(:ok), do: :ok

  defp normalize_engine_result({:error, :engine_failure, message}) when is_binary(message) do
    {:error, :engine_failure, message}
  end

  defp normalize_engine_result({:error, :engine_failure, _message}) do
    {:error, :engine_failure, "engine failure"}
  end

  defp normalize_engine_result({:error, :internal, message}) when is_binary(message) do
    {:error, :internal, message}
  end

  defp normalize_engine_result(_other) do
    {:error, :engine_failure, "engine failure"}
  end

  defp validate_payload(%{
         "profile" => profile,
         "button_id" => button_id,
         "request_id" => request_id
       })
       when is_binary(profile) and profile != "" and is_binary(button_id) and button_id != "" and
              is_binary(request_id) and request_id != "" do
    :ok
  end

  defp validate_payload(_), do: {:error, "invalid_request"}

  defp fetch_config(provider) do
    _ = Code.ensure_loaded(provider)

    cond do
      function_exported?(provider, :get_config, 0) -> provider.get_config()
      function_exported?(provider, :load, 0) -> provider.load()
      true -> {:error, :not_configured}
    end
  end

  defp ensure_engine_available(engine) do
    _ = Code.ensure_loaded(engine)

    if engine.available?() do
      :ok
    else
      {:error, :engine_unavailable}
    end
  rescue
    UndefinedFunctionError ->
      {:error, :engine_unavailable}
  end

  defp ensure_macro_exists(%LoadConfig.Config{profiles: profiles}, profile_name, button_id)
       when is_list(profiles) and is_binary(profile_name) and is_binary(button_id) do
    found? =
      Enum.any?(profiles, fn %{raw: raw} ->
        get_in(raw, ["name"]) == profile_name and
          Enum.any?(get_in(raw, ["buttons"]) || [], fn b -> get_in(b, ["id"]) == button_id end)
      end)

    if found?, do: :ok, else: {:error, :not_found}
  end

  defp ensure_macro_exists(_config, _profile_name, _button_id), do: {:error, :not_found}

  defp fetch_sequence(%LoadConfig.Config{profiles: profiles}, profile_name, button_id)
       when is_list(profiles) and is_binary(profile_name) and is_binary(button_id) do
    profile_raw =
      Enum.find_value(profiles, %{}, fn %{raw: raw} ->
        if get_in(raw, ["name"]) == profile_name, do: raw, else: nil
      end)

    buttons = get_in(profile_raw, ["buttons"]) || []

    button_raw =
      Enum.find_value(buttons, %{}, fn b ->
        if get_in(b, ["id"]) == button_id, do: b, else: nil
      end)

    seq = get_in(button_raw, ["sequence"])
    if is_list(seq), do: seq, else: []
  end

  defp fetch_sequence(_config, _profile_name, _button_id), do: []
end
