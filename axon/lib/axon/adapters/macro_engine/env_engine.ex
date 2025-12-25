defmodule Axon.Adapters.MacroEngine.EnvEngine do
  @moduledoc false

  @default_opts [available: true, result: :ok, delay_ms: 0]

  def available? do
    opts = Application.get_env(:axon, :macro_engine, @default_opts)
    Keyword.get(opts, :available, true)
  end

  def run(_profile, _button_id, _request_id) do
    step_result()
  end

  def key_down(_key), do: step_result()
  def key_up(_key), do: step_result()
  def key_tap(_key), do: step_result()

  defp step_result do
    opts = Application.get_env(:axon, :macro_engine, @default_opts)

    delay_ms = Keyword.get(opts, :delay_ms, 0)

    if is_integer(delay_ms) and delay_ms > 0 do
      Process.sleep(delay_ms)
    end

    case Keyword.get(opts, :result, :ok) do
      :ok ->
        :ok

      :error ->
        {:error, :engine_failure, "engine failure"}
    end
  end

  def panic do
    opts = Application.get_env(:axon, :macro_engine, @default_opts)

    notify_pid = Keyword.get(opts, :panic_notify_pid)

    if is_pid(notify_pid) do
      send(notify_pid, {:engine_panic_called, self()})
    end

    delay_ms = Keyword.get(opts, :panic_delay_ms, 0)

    if is_integer(delay_ms) and delay_ms > 0 do
      Process.sleep(delay_ms)
    end

    :ok
  end
end
