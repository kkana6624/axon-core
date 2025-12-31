defmodule Axon.Adapters.MacroEngine.NifEngine do
  @moduledoc false

  use Rustler, otp_app: :axon, crate: "axon_engine"

  @engine_unavailable {:error, :engine_unavailable, "engine unavailable"}

  # NIFs (replaced by Rustler)
  def available_nif, do: :erlang.nif_error(:nif_not_loaded)
  def key_down_nif(_key), do: :erlang.nif_error(:nif_not_loaded)
  def key_up_nif(_key), do: :erlang.nif_error(:nif_not_loaded)
  def key_tap_nif(_key), do: :erlang.nif_error(:nif_not_loaded)
  def execute_sequence_nif(_actions), do: :erlang.nif_error(:nif_not_loaded)
  def panic_nif, do: :erlang.nif_error(:nif_not_loaded)
  def dump_keycodes_nif, do: :erlang.nif_error(:nif_not_loaded)
  def get_wlan_interfaces_nif, do: :erlang.nif_error(:nif_not_loaded)
  def start_mdns_nif(_service_type, _instance_name, _port), do: :erlang.nif_error(:nif_not_loaded)
  def stop_mdns_nif(_ref), do: :erlang.nif_error(:nif_not_loaded)
  def run_privileged_command_nif(_cmd, _params), do: :erlang.nif_error(:nif_not_loaded)

  # Adapter API expected by Axon.App.Macro.TapMacro
  def available? do
    available_nif()
  rescue
    _ -> false
  catch
    :exit, _ -> false
    _, _ -> false
  end

  def key_down(key) when is_binary(key) do
    with {:ok, atom_key} <- to_key_atom(key) do
      key_down_nif(atom_key) |> normalize_nif_result()
    else
      {:error, _} -> {:error, :config_invalid, "invalid key: #{key}"}
    end
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  def key_up(key) when is_binary(key) do
    with {:ok, atom_key} <- to_key_atom(key) do
      key_up_nif(atom_key) |> normalize_nif_result()
    else
      {:error, _} -> {:error, :config_invalid, "invalid key: #{key}"}
    end
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  def key_tap(key) when is_binary(key) do
    with {:ok, atom_key} <- to_key_atom(key) do
      key_tap_nif(atom_key) |> normalize_nif_result()
    else
      {:error, _} -> {:error, :config_invalid, "invalid key: #{key}"}
    end
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  def execute_sequence(sequence) when is_list(sequence) do
    with {:ok, nif_actions} <- prepare_actions(sequence) do
      execute_sequence_nif(nif_actions) |> normalize_nif_result()
    end
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  defp prepare_actions(sequence) do
    result =
      Enum.reduce_while(sequence, {:ok, []}, fn step, {:ok, acc} ->
        case map_step_to_nif(step) do
          {:ok, nif_step} -> {:cont, {:ok, [nif_step | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case result do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp map_step_to_nif(%{"action" => "wait", "value" => v}), do: {:ok, {:wait, v}}
  defp map_step_to_nif(%{"action" => "panic"}), do: {:ok, :panic}

  defp map_step_to_nif(%{"action" => action, "key" => key}) do
    with {:ok, atom_key} <- to_key_atom(key) do
      case action do
        "down" -> {:ok, {:key_down, atom_key}}
        "up" -> {:ok, {:key_up, atom_key}}
        "tap" -> {:ok, {:key_tap, atom_key}}
        _ -> {:error, :invalid_action}
      end
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp map_step_to_nif(_), do: {:error, :invalid_step}

  def panic do
    _ = panic_nif()
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
    _, _ -> :ok
  end

  # Setup API
  def get_wlan_interfaces do
    case get_wlan_interfaces_nif() do
      {:ok, json} ->
        Jason.decode(json)

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  def start_mdns(service_type, instance_name, port) do
    start_mdns_nif(service_type, instance_name, port)
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  def stop_mdns(ref) do
    stop_mdns_nif(ref)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
    _, _ -> :ok
  end

  def run_privileged_command(cmd, params) do
    run_privileged_command_nif(cmd, params)
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  defp normalize_nif_result({:ok, :ok}), do: :ok
  defp normalize_nif_result({:error, {:error, reason, message}}), do: {:error, reason, message}
  defp normalize_nif_result(other), do: other

  # Mapping from String ("VK_A") to Atom (:vk_a) matching Rust Key enum
  defp to_key_atom(key) do
    case key do
      "VK_A" -> {:ok, :vk_a}
      "VK_B" -> {:ok, :vk_b}
      "VK_C" -> {:ok, :vk_c}
      "VK_D" -> {:ok, :vk_d}
      "VK_E" -> {:ok, :vk_e}
      "VK_F" -> {:ok, :vk_f}
      "VK_G" -> {:ok, :vk_g}
      "VK_H" -> {:ok, :vk_h}
      "VK_I" -> {:ok, :vk_i}
      "VK_J" -> {:ok, :vk_j}
      "VK_K" -> {:ok, :vk_k}
      "VK_L" -> {:ok, :vk_l}
      "VK_M" -> {:ok, :vk_m}
      "VK_N" -> {:ok, :vk_n}
      "VK_O" -> {:ok, :vk_o}
      "VK_P" -> {:ok, :vk_p}
      "VK_Q" -> {:ok, :vk_q}
      "VK_R" -> {:ok, :vk_r}
      "VK_S" -> {:ok, :vk_s}
      "VK_T" -> {:ok, :vk_t}
      "VK_U" -> {:ok, :vk_u}
      "VK_V" -> {:ok, :vk_v}
      "VK_W" -> {:ok, :vk_w}
      "VK_X" -> {:ok, :vk_x}
      "VK_Y" -> {:ok, :vk_y}
      "VK_Z" -> {:ok, :vk_z}
      "VK_LSHIFT" -> {:ok, :vk_lshift}
      "VK_RSHIFT" -> {:ok, :vk_rshift}
      "VK_LCTRL" -> {:ok, :vk_lcontrol}
      "VK_RCTRL" -> {:ok, :vk_rcontrol}
      "VK_LMENU" -> {:ok, :vk_lmenu}
      "VK_RMENU" -> {:ok, :vk_rmenu}
      "VK_RETURN" -> {:ok, :vk_return}
      "VK_SPACE" -> {:ok, :vk_space}
      "VK_BACK" -> {:ok, :vk_back}
      "VK_TAB" -> {:ok, :vk_tab}
      "VK_ESCAPE" -> {:ok, :vk_escape}
      "VK_UP" -> {:ok, :vk_up}
      "VK_DOWN" -> {:ok, :vk_down}
      "VK_LEFT" -> {:ok, :vk_left}
      "VK_RIGHT" -> {:ok, :vk_right}
      _ -> {:error, :unknown_key}
    end
  end
end
