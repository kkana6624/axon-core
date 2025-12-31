defmodule AxonWeb.DashboardLive do
  use AxonWeb, :live_view

  alias Axon.App.LoadConfig
  alias Axon.App.ExecuteMacro
  alias Axon.App.Setup.MdnsServer

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_data(socket)}
  end

  @impl true
  def handle_event("run_macro", %{"profile" => profile, "button" => button}, socket) do
    request_id = "test-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16())
    payload = %{
      "profile" => profile,
      "button_id" => button,
      "request_id" => request_id
    }

    case ExecuteMacro.tap_macro(payload) do
      {:accepted, _ack} ->
        {:noreply, put_flash(socket, :info, "Macro '#{button}' started.")}

      {:rejected, %{"reason" => reason}} ->
        {:noreply, put_flash(socket, :error, "Macro rejected: #{reason}")}
    end
  end

  @impl true
  def handle_info({:emit_macro_result, %{"status" => status, "request_id" => _rid} = result}, socket) do
    message =
      case status do
        "ok" -> "Macro execution finished successfully."
        "panic" -> "Emergency Panic triggered!"
        "error" -> "Macro failed: #{result["message"] || result["error_code"]}"
        _ -> "Macro finished with status: #{status}"
      end

    level = if status == "ok", do: :info, else: :error
    {:noreply, put_flash(socket, level, message)}
  end

  defp assign_data(socket) do
    config_result = LoadConfig.load()
    mdns_status = MdnsServer.get_status()

    assign(socket,
      config_result: config_result,
      mdns_status: mdns_status,
      loading: false
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <nav class="bg-gray-800 text-white shadow-lg">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex items-center justify-between h-16">
            <div class="flex items-center">
              <span class="text-xl font-bold tracking-tight">AXON Dashboard</span>
            </div>
            <div class="flex items-center space-x-4">
              <div class="flex items-center text-xs">
                <span class={"inline-block w-2 h-2 rounded-full mr-2 #{if @mdns_status == :running, do: "bg-green-400 animate-pulse", else: "bg-gray-500"}"}></span>
                mDNS: <%= String.capitalize(to_string(@mdns_status)) %>
              </div>
              <a href={~p"/setup"} class="text-sm bg-gray-700 hover:bg-gray-600 px-3 py-1 rounded transition">Setup</a>
            </div>
          </div>
        </div>
      </nav>

      <main class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <Layouts.flash_group flash={@flash} />

        <%= case @config_result do %>
          <% {:ok, config} -> %>
            <div class="grid grid-cols-1 gap-6">
              <%= for profile <- config.profiles do %>
                <div class="bg-white shadow rounded-lg overflow-hidden border border-gray-200">
                  <div class="bg-gray-50 px-6 py-4 border-b border-gray-200 flex justify-between items-center">
                    <h2 class="text-lg font-bold text-gray-800"><%= profile.name %></h2>
                    <span class="text-xs font-mono text-gray-400">Profile</span>
                  </div>
                  <div class="p-6">
                    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                      <%= for button <- get_in(profile.raw, ["buttons"]) || [] do %>
                        <button
                          phx-click="run_macro"
                          phx-value-profile={profile.name}
                          phx-value-button={button["id"]}
                          class="flex flex-col items-center justify-center p-4 rounded-xl bg-white border-2 border-gray-100 hover:border-blue-500 hover:bg-blue-50 hover:shadow-md transition group"
                        >
                          <div class="w-10 h-10 rounded-lg bg-gray-100 group-hover:bg-blue-100 flex items-center justify-center mb-2 transition">
                            <.icon name="hero-command-line" class="w-6 h-6 text-gray-500 group-hover:text-blue-600" />
                          </div>
                          <span class="text-xs font-bold text-gray-700 group-hover:text-blue-700 text-center line-clamp-2"><%= button["label"] || button["id"] %></span>
                        </button>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>

          <% {:error, _reason} -> %>
            <div class="bg-white shadow rounded-lg p-12 text-center border-2 border-dashed border-red-200">
              <.icon name="hero-exclamation-triangle" class="w-12 h-12 text-red-500 mx-auto mb-4" />
              <h2 class="text-xl font-bold text-gray-800 mb-2">Configuration Issue</h2>
              <p class="text-gray-600 mb-6">There was a problem loading your profiles. Please check the setup page for details.</p>
              <a href={~p"/setup"} class="inline-block bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-6 rounded transition">
                Go to Setup
              </a>
            </div>
        <% end %>
      </main>
    </div>
    """
  end
end
