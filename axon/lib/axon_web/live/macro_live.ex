defmodule AxonWeb.MacroLive do
  @moduledoc false

  use AxonWeb, :live_view

  alias Axon.App.ExecuteMacro

  defp config_provider, do: Application.get_env(:axon, :config_provider)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        config_provider().subscribe()
        
        push_event(socket, "server_info", %{
          "version" => Mix.Project.config()[:version],
          "capabilities" => ["tap_macro", "panic", "vibrate"]
        })
      else
        socket
      end

    {:ok, assign_data(socket)}
  end

  @impl true
  def handle_info({:config_updated, _ref}, socket) do
    {:noreply, assign_data(socket)}
  end

  @impl true
  def handle_info({:emit_macro_result, payload}, socket) do
    status =
      case payload["status"] do
        "ok" -> :ready
        "panic" -> :panic
        _ -> :error
      end

    {:noreply, socket |> assign(status: status) |> push_event("macro_result", payload)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-slate-50 overflow-hidden font-sans text-slate-900 select-none">
      <!-- Material Top App Bar -->
      <header class="flex items-center justify-between px-4 py-3 bg-white shadow-sm z-10">
        <div class="flex items-center gap-3">
          <div class="p-2 rounded-full hover:bg-slate-100 transition-colors active:bg-slate-200">
            <.icon name="hero-bars-3" class="w-6 h-6" />
          </div>
          <h1 class="text-xl font-medium tracking-tight">AXON Macro</h1>
        </div>
        <div class="flex items-center gap-2">
          <div class={"px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider transition-all duration-300 #{case @status do
            :ready -> "bg-green-100 text-green-700 border border-green-200"
            :busy -> "bg-amber-100 text-amber-700 border border-amber-200 animate-pulse"
            :panic -> "bg-orange-100 text-orange-700 border border-orange-200"
            :error -> "bg-red-100 text-red-700 border border-red-200"
          end}"}>
            <%= @status %>
          </div>
        </div>
      </header>

      <!-- Profile Tabs -->
      <div class="flex overflow-x-auto bg-white border-b border-slate-200 scrollbar-hide shrink-0">
        <%= if @config do %>
          <%= for profile <- @config.profiles do %>
            <button
              phx-click="select_profile"
              phx-value-name={profile.name}
              class={"px-6 py-4 text-sm font-medium transition-all relative whitespace-nowrap #{if @current_profile.name == profile.name, do: "text-blue-600", else: "text-slate-500 hover:text-slate-700"}"}
            >
              <%= profile.name %>
              <%= if @current_profile.name == profile.name do %>
                <div class="absolute bottom-0 left-0 right-0 h-0.5 bg-blue-600 rounded-t-full"></div>
              <% end %>
            </button>
          <% end %>
        <% end %>
      </div>

      <!-- Button Grid -->
      <main class="flex-grow overflow-y-auto p-4 pb-24">
        <%= if @current_profile do %>
          <div class="grid grid-cols-2 xs:grid-cols-3 gap-3 max-w-lg mx-auto">
            <%= for button <- get_in(@current_profile.raw, ["buttons"]) || [] do %>
              <button
                phx-click="tap_macro"
                phx-value-id={button["id"]}
                class="aspect-square flex flex-col items-center justify-center p-4 bg-white rounded-2xl shadow-sm border border-slate-100 active:scale-95 active:shadow-inner active:bg-slate-50 transition-all group overflow-hidden relative"
              >
                <div class="w-12 h-12 rounded-full bg-slate-50 group-active:bg-blue-50 flex items-center justify-center mb-3 transition-colors">
                  <.icon name="hero-command-line" class="w-6 h-6 text-slate-400 group-active:text-blue-600" />
                </div>
                <span class="text-xs font-bold text-slate-700 text-center line-clamp-2 leading-tight uppercase tracking-wide">
                  <%= button["label"] || button["id"] %>
                </span>
              </button>
            <% end %>
          </div>
        <% else %>
          <div class="flex flex-col items-center justify-center h-full text-slate-400 italic text-sm text-center p-8">
            <.icon name="hero-exclamation-circle" class="w-12 h-12 mb-4 opacity-20" />
            No profiles loaded. Please check your configuration.
          </div>
        <% end %>
      </main>

      <!-- Panic Floating Action Button -->
      <button
        phx-click="panic"
        class="fixed bottom-6 right-6 w-14 h-14 bg-red-600 text-white rounded-full shadow-lg shadow-red-200 flex items-center justify-center active:scale-90 active:bg-red-700 transition-all z-20"
      >
        <.icon name="hero-bolt" class="w-7 h-7" />
      </button>

      <!-- Panic/Error Recovery Overlay -->
      <%= if @status in [:panic, :error] do %>
        <div class="fixed inset-0 bg-slate-900/80 backdrop-blur-sm z-30 flex items-center justify-center p-6 text-center">
          <div class="bg-white rounded-3xl p-8 shadow-2xl max-w-xs w-full animate-in fade-in zoom-in duration-300">
            <div class={"w-20 h-20 rounded-full mx-auto mb-6 flex items-center justify-center #{if @status == :panic, do: "bg-orange-100 text-orange-600", else: "bg-red-100 text-red-600"}"}>
              <.icon name={if @status == :panic, do: "hero-exclamation-triangle", else: "hero-x-circle"} class="w-10 h-10" />
            </div>
            <h2 class="text-2xl font-bold mb-2">
              <%= if @status == :panic, do: "Panic Mode", else: "System Error" %>
            </h2>
            <p class="text-slate-500 mb-8 leading-relaxed">
              <%= if @status == :panic, do: "Emergency stop was triggered. All keys have been released.", else: "A system error occurred while executing the macro." %>
            </p>
            <button
              phx-click="panic_reset"
              class="w-full py-4 bg-slate-900 text-white rounded-2xl font-bold text-lg active:scale-95 transition-transform"
            >
              RESET SYSTEM
            </button>
          </div>
        </div>
      <% end %>

      <!-- Feedback Toast Area (CSS handles visibility) -->
      <div id="status-toast" class="fixed bottom-24 left-1/2 -translate-x-1/2 px-4 py-2 bg-slate-800 text-white text-xs rounded-full opacity-0 pointer-events-none transition-opacity duration-300">
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_profile", %{"name" => name}, socket) do
    profile = Enum.find(socket.assigns.config.profiles, fn p -> p.name == name end)
    {:noreply, assign(socket, current_profile: profile)}
  end

  @impl true
  def handle_event("tap_macro", payload, socket) when is_map(payload) do
    button_id = Map.get(payload, "id") || Map.get(payload, "button_id")

    if is_nil(button_id) or button_id == "" do
      ack = %{"accepted" => false, "reason" => "invalid_request", "request_id" => Map.get(payload, "request_id")}
      {:noreply, push_event(socket, "macro_ack", ack)}
    else
      # Support both mobile UI (just "id") and full API payload (for tests/Android client)
      profile_name = Map.get(payload, "profile") || (socket.assigns.current_profile && socket.assigns.current_profile.name)
      request_id = Map.get(payload, "request_id") || ("mob-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16()))

      full_payload = %{
        "profile" => profile_name,
        "button_id" => button_id,
        "request_id" => request_id
      }

      # Haptic feedback (send event to client)
      socket = push_event(socket, "vibrate", %{ms: 50})

      case ExecuteMacro.tap_macro(full_payload, reply_to: self(), owner_pid: self()) do
        {:rejected, ack} ->
          status = if ack["reason"] == "busy", do: :busy, else: :error
          {:noreply, socket |> assign(status: status) |> push_event("macro_ack", ack)}

        {:accepted, ack} ->
          {:noreply, socket |> assign(status: :busy) |> push_event("macro_ack", ack)}
      end
    end
  end

  @impl true
  def handle_event("panic", payload, socket) when is_map(payload) do
    request_id = Map.get(payload, "request_id") || ("mob-panic-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16()))
    full_payload = %{"request_id" => request_id}

    socket = push_event(socket, "vibrate", %{ms: 200})

    case ExecuteMacro.panic(full_payload, reply_to: self()) do
      {:rejected, ack} ->
        {:noreply, push_event(socket, "macro_ack", ack)}

      {:accepted, ack} ->
        {:noreply, assign(socket, status: :ready) |> push_event("macro_ack", ack)}
    end
  end

  @impl true
  def handle_event("panic", _params, socket) do
    handle_event("panic", %{}, socket)
  end

  @impl true
  def handle_event("panic_reset", _params, socket) do
    :ok = ExecuteMacro.panic_reset()
    {:noreply, assign(socket, status: :ready)}
  end

  defp assign_data(socket) do
    case config_provider().get_config() do
      {:ok, config} ->
        # Select first profile by default if not set
        current_profile = socket.assigns[:current_profile] || List.first(config.profiles)

        assign(socket,
          config: config,
          current_profile: current_profile,
          status: socket.assigns[:status] || :ready
        )

      {:error, _reason} ->
        if Mix.env() == :test do
          assign(socket, config: nil, current_profile: nil, status: socket.assigns[:status] || :ready)
        else
          # SetupPlug will handle redirect, but for robustness:
          assign(socket, config: nil, current_profile: nil, status: :error)
        end
    end
  end
end
