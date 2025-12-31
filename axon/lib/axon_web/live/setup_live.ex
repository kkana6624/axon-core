defmodule AxonWeb.SetupLive do
  use AxonWeb, :live_view

  alias Axon.App.LoadConfig
  alias Axon.App.Setup.GetNicCapabilities
  alias Axon.App.Setup.MdnsServer
  alias Axon.App.Setup.SetupFirewall
  alias Axon.Adapters.Config.ProfilesPath

  @impl true
  def mount(_params, _session, socket) do
    peer_data = get_connect_info(socket, :peer_data) || %{address: {0, 0, 0, 0}}
    
    if connected?(socket) do
      send(self(), :async_init)
      :timer.send_interval(2000, :tick)
    end

    {:ok, 
     socket 
     |> assign(client_ip: peer_data.address)
     |> assign(
       config_result: {:ok, %{profiles: []}}, # Placeholder
       profiles_path_result: {:ok, ""},
       nic_result: {:ok, []},
       mdns_status: :stopped,
       firewall_configured: false,
       security_config: [],
       all_ips: [],
       loading: true,
       firewall_error: nil,
       env_var: "AXON_PROFILES_PATH",
       env_value: System.get_env("AXON_PROFILES_PATH")
     )}
  end

  @impl true
  def handle_info(:async_init, socket) do
    {:noreply, socket |> assign_data() |> assign(loading: false)}
  end

  @impl true
  def handle_info(:tick, socket) do
    # Only reload config, skip heavy system checks
    {:noreply, reload_config_data(socket)}
  end

  @impl true
  def handle_event("reload_config", _params, socket) do
    {:noreply, reload_config_data(socket)}
  end

  @impl true
  def handle_event("setup_firewall", _params, socket) do
    case SetupFirewall.execute() do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Firewall rules created successfully.")
         |> assign(firewall_configured: SetupFirewall.configured?())}

      {:error, reason} ->
        {:noreply, assign(socket, firewall_error: reason)}
    end
  end

  @impl true
  def handle_event("refresh_firewall", _params, socket) do
    {:noreply, assign(socket, firewall_configured: SetupFirewall.configured?())}
  end

  @impl true
  def handle_event("start_mdns", %{"port" => port_str}, socket) do
    port = String.to_integer(port_str)
    # Default values for now
    case MdnsServer.start_broadcast("_axon-macro._tcp.local.", "AxonServer", port) do
      :ok ->
        {:noreply, assign(socket, mdns_status: :running)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start mDNS: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop_mdns", _params, socket) do
    MdnsServer.stop_broadcast()
    {:noreply, assign(socket, mdns_status: :stopped)}
  end

  @impl true
  def handle_event("test_tap", %{"key" => key}, socket) do
    engine = Application.get_env(:axon, :macro_engine_module)

    case engine.key_tap(key) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Direct engine tap '#{key}' successful.")}

      {:error, :config_invalid, message} ->
        {:noreply, put_flash(socket, :error, "Engine test failed (Invalid Config): #{message}")}

      {:error, _reason, message} ->
        {:noreply, put_flash(socket, :error, "Engine test failed: #{message}")}
    end
  end

  defp assign_data(socket) do
    config_result = LoadConfig.load()
    profiles_path_result = ProfilesPath.resolve()
    nic_result = GetNicCapabilities.execute()
    mdns_status = MdnsServer.get_status()
    firewall_configured = SetupFirewall.configured?()
    security_config = Application.get_env(:axon, :remote_address, [])
    all_ips = list_all_ips()

    assign(socket,
      config_result: config_result,
      profiles_path_result: profiles_path_result,
      nic_result: nic_result,
      mdns_status: mdns_status,
      firewall_configured: firewall_configured,
      security_config: security_config,
      all_ips: all_ips,
      loading: false,
      firewall_error: nil,
      env_var: "AXON_PROFILES_PATH",
      env_value: System.get_env("AXON_PROFILES_PATH")
    )
  end

  defp reload_config_data(socket) do
    config_result = LoadConfig.load()
    profiles_path_result = ProfilesPath.resolve()
    
    assign(socket,
      config_result: config_result,
      profiles_path_result: profiles_path_result,
      env_value: System.get_env("AXON_PROFILES_PATH")
    )
  end

  defp list_all_ips do
    case :inet.getifaddrs() do
      {:ok, ifaddrs} ->
        for {ifname, opts} <- ifaddrs,
            {addr_type, addr} <- opts,
            addr_type == :addr,
            tuple_size(addr) == 4,
            addr != {127, 0, 0, 1} do
          %{ifname: List.to_string(ifname), addr: :inet.ntoa(addr)}
        end

      _ ->
        []
    end
  end

  defp format_config_error({:unknown_key, %{key: key, profile: p, button_id: b, sequence_index: i}}) do
    "Unknown key '#{key}' in profile '#{p}', button '#{b}' at action ##{i + 1}."
  end

  defp format_config_error({:invalid_action, %{action: a, profile: p, button_id: b, sequence_index: i}}) do
    "Invalid action '#{a}' in profile '#{p}', button '#{b}' at action ##{i + 1}."
  end

  defp format_config_error({:duplicate_button_id, %{button_id: id, profile: p}}) do
    "Duplicate button ID '#{id}' in profile '#{p}'."
  end

  defp format_config_error({:wait_total_exceeded, %{total_ms: total, limit_ms: limit, profile: p, button_id: b}}) do
    "Total wait time (#{total}ms) exceeds limit (#{limit}ms) in profile '#{p}', button '#{b}'."
  end

  defp format_config_error({:sequence_too_long, %{length: len, limit: limit, profile: p, button_id: b}}) do
    "Sequence length (#{len}) exceeds limit (#{limit}) in profile '#{p}', button '#{b}'."
  end

  defp format_config_error({:unsupported_version, v}), do: "Unsupported configuration version: #{v}. Only version 1 is supported."
  defp format_config_error(:missing_version), do: "Missing 'version' field in configuration."
  defp format_config_error(:empty_profiles), do: "No profiles found in configuration."
  defp format_config_error(reason), do: "Invalid configuration format: #{inspect(reason)}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">Axon Setup Wizard</h1>
        <%= if @loading do %>
          <div class="flex items-center text-blue-600 animate-pulse">
            <.icon name="hero-arrow-path" class="w-5 h-5 mr-2 animate-spin" />
            <span class="text-sm font-medium">Detecting system environment...</span>
          </div>
        <% end %>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 relative">
        <%= if @loading do %>
          <div class="absolute inset-0 bg-white/50 backdrop-blur-[1px] z-20 rounded-lg flex items-center justify-center">
          </div>
        <% end %>
        <!-- Configuration Section -->
        <div class="bg-white shadow rounded-lg p-6 border-t-4 border-blue-500">
          <h2 class="text-xl font-semibold mb-4 flex items-center">
            <.icon name="hero-cog-6-tooth" class="w-5 h-5 mr-2" /> Configuration
          </h2>

          <%= case @config_result do %>
            <% {:ok, _config} -> %>
              <div class="bg-green-100 text-green-800 p-3 rounded mb-4">
                <p class="flex items-center font-medium">
                  <.icon name="hero-check-circle" class="w-5 h-5 mr-2" /> Profiles loaded successfully
                </p>
              </div>
            <% {:error, reason} -> %>
              <div class="bg-red-100 text-red-800 p-3 rounded mb-4">
                <p class="flex items-center font-medium">
                  <.icon name="hero-exclamation-triangle" class="w-5 h-5 mr-2" /> Configuration Error
                </p>
                <p class="text-sm mt-1 font-bold"><%= format_config_error(reason) %></p>
                <div class="mt-2 p-2 bg-white/50 rounded text-[10px] font-mono overflow-auto max-h-20">
                  Raw: <%= inspect(reason) %>
                </div>
              </div>
          <% end %>

          <div class="text-sm space-y-2 mb-4">
            <p><strong>Path resolved to:</strong></p>
            <pre class="bg-gray-100 p-2 rounded text-xs break-all"><%= case @profiles_path_result do
              {:ok, path} -> path
              other -> inspect(other)
            end %></pre>
            <p><strong>Environment Var:</strong> <%= @env_var %>=<span class="font-mono bg-gray-100 px-1 rounded"><%= @env_value || "(not set)" %></span></p>
          </div>

          <button phx-click="reload_config" class="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded transition duration-200">
            Reload Configuration
          </button>
        </div>

        <!-- Network Section -->
        <div class="bg-white shadow rounded-lg p-6 border-t-4 border-green-500">
          <h2 class="text-xl font-semibold mb-4 flex items-center">
            <.icon name="hero-signal" class="w-5 h-5 mr-2" /> Network & mDNS
          </h2>

          <div class="mb-4">
            <h3 class="text-sm font-bold text-gray-700 mb-2 uppercase tracking-wider">Local IP Addresses</h3>
            <ul class="space-y-1 mb-4">
              <%= for ip_info <- @all_ips do %>
                <li class="text-sm flex justify-between bg-slate-50 px-2 py-1 rounded">
                  <span class="text-gray-500 font-mono text-xs"><%= ip_info.ifname %></span>
                  <span class="font-bold font-mono text-blue-600"><%= ip_info.addr %></span>
                </li>
              <% end %>
              <%= if Enum.empty?(@all_ips) do %>
                <li class="text-sm text-gray-500 italic">No non-loopback IPv4 addresses found.</li>
              <% end %>
            </ul>

            <h3 class="text-sm font-bold text-gray-700 mb-2 uppercase tracking-wider">WLAN Interfaces</h3>
            <%= case @nic_result do %>
              <% {:ok, interfaces} -> %>
                <ul class="space-y-2">
                  <%= for iface <- interfaces do %>
                    <li class="text-sm bg-gray-50 p-2 rounded border border-gray-200">
                      <div class="font-medium"><%= iface["description"] %></div>
                      <div class="text-xs text-gray-500 font-mono"><%= iface["guid"] %></div>
                    </li>
                  <% end %>
                  <%= if Enum.empty?(interfaces) do %>
                    <li class="text-sm text-gray-500 italic">No WLAN interfaces found.</li>
                  <% end %>
                </ul>
              <% {:error, _code, message} -> %>
                <div class="text-sm text-red-600 font-medium">Error: <%= message %></div>
              <% {:error, reason} -> %>
                <div class="text-sm text-red-600 font-medium">Error: <%= inspect(reason) %></div>
            <% end %>
          </div>

          <div class="pt-4 border-t border-gray-100">
            <h3 class="text-sm font-bold text-gray-700 mb-2 uppercase tracking-wider">Service Discovery (mDNS)</h3>
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center">
                <div class={"w-3 h-3 rounded-full mr-2 #{if @mdns_status == :running, do: "bg-green-500 animate-pulse", else: "bg-gray-400"}"}></div>
                <span class="text-sm font-medium"><%= String.capitalize(to_string(@mdns_status)) %></span>
              </div>

              <%= if @mdns_status == :stopped do %>
                <button phx-click="start_mdns" phx-value-port="4000" class="text-xs bg-green-600 hover:bg-green-700 text-white py-1 px-3 rounded">
                  Start Broadcast
                </button>
              <% else %>
                <button phx-click="stop_mdns" class="text-xs bg-red-600 hover:bg-red-700 text-white py-1 px-3 rounded">
                  Stop
                </button>
              <% end %>
            </div>
            <p class="text-xs text-gray-500 mb-2">Broadcasting as:</p>
            <div class="bg-gray-800 text-green-400 font-mono text-xs p-2 rounded break-all mb-2">
              AxonServer._axon-macro._tcp.local.
            </div>
            <p class="text-[10px] text-gray-400 italic">Port: 4000</p>
          </div>
        </div>

        <!-- Security Section -->
        <div class="bg-white shadow rounded-lg p-6 border-t-4 border-red-500">
          <h2 class="text-xl font-semibold mb-4 flex items-center">
            <.icon name="hero-lock-closed" class="w-5 h-5 mr-2" /> Security
          </h2>
          
          <div class="mb-4">
            <div class="flex justify-between items-center mb-2">
              <span class="text-sm font-bold text-gray-700 uppercase tracking-wider">Your IP Address</span>
              <span class="text-xs font-mono bg-gray-100 px-2 py-1 rounded"><%= :inet.ntoa(@client_ip) %></span>
            </div>
            
            <div class={"p-3 rounded flex items-center #{if Axon.Adapters.Security.RemoteAddress.allowed?(@client_ip, @security_config), do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800"}"}>
              <.icon name={if Axon.Adapters.Security.RemoteAddress.allowed?(@client_ip, @security_config), do: "hero-check-circle", else: "hero-x-circle"} class="w-5 h-5 mr-2" />
              <span class="text-sm font-medium">
                <%= if Axon.Adapters.Security.RemoteAddress.allowed?(@client_ip, @security_config), do: "Access allowed from this IP", else: "Access restricted from this IP" %>
              </span>
            </div>
          </div>

          <div class="space-y-2">
            <h3 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Policy Settings</h3>
            <div class="flex items-center justify-between text-sm">
              <span>Allow Loopback</span>
              <span class={"font-bold #{if @security_config[:allow_loopback] != false, do: "text-green-600", else: "text-red-600"}"}>
                <%= if @security_config[:allow_loopback] != false, do: "YES", else: "NO" %>
              </span>
            </div>
            <div class="flex items-center justify-between text-sm">
              <span>Allow Private Ranges</span>
              <span class={"font-bold #{if @security_config[:allow_private] != false, do: "text-green-600", else: "text-red-600"}"}>
                <%= if @security_config[:allow_private] != false, do: "YES", else: "NO" %>
              </span>
            </div>
          </div>
          <p class="mt-4 text-[10px] text-gray-400 italic">To change policy, edit config/config.exs and restart the server.</p>
        </div>

        <!-- Firewall Section -->
        <div class="bg-white shadow rounded-lg p-6 border-t-4 border-orange-500 md:col-span-2">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-xl font-semibold flex items-center">
              <.icon name="hero-shield-check" class="w-5 h-5 mr-2" /> Windows Firewall
            </h2>
            <div class="flex items-center space-x-2">
              <%= if @firewall_configured do %>
                <span class="bg-green-100 text-green-700 text-xs font-bold px-2 py-1 rounded flex items-center">
                  <.icon name="hero-check-badge" class="w-3 h-3 mr-1" /> Configured
                </span>
              <% else %>
                <span class="bg-gray-100 text-gray-600 text-xs font-bold px-2 py-1 rounded flex items-center">
                  <.icon name="hero-x-circle" class="w-3 h-3 mr-1" /> Not Detected
                </span>
              <% end %>
              <button phx-click="refresh_firewall" class="p-1 hover:bg-gray-100 rounded transition" title="Refresh status">
                <.icon name="hero-arrow-path" class="w-4 h-4 text-gray-500" />
              </button>
            </div>
          </div>

          <div class="flex flex-col md:flex-row gap-6">
            <div class="md:w-1/2">
              <p class="text-sm text-gray-600 mb-4">
                To allow Android devices to discover and connect to this PC, we need to open TCP port 4000 and UDP port 5353.
              </p>

              <button phx-click="setup_firewall" class="bg-orange-600 hover:bg-orange-700 text-white font-bold py-2 px-6 rounded transition duration-200 flex items-center">
                <.icon name="hero-bolt" class="w-4 h-4 mr-2" />
                <%= if @firewall_configured, do: "Repair / Re-apply Rules", else: "Automatic Setup (Requires UAC)" %>
              </button>

              <%= if @firewall_error do %>
                <div class="mt-4 bg-orange-100 text-orange-800 p-3 rounded text-sm">
                  <p class="font-bold text-xs uppercase mb-1">Automatic setup failed or was canceled</p>
                  <p><%= @firewall_error %></p>
                </div>
              <% end %>
            </div>

            <div class="md:w-1/2">
              <h3 class="text-xs font-bold text-gray-500 mb-2 uppercase tracking-wider">Manual Setup (PowerShell)</h3>
              <p class="text-xs text-gray-500 mb-2">If automatic setup fails, run this as Administrator:</p>
              <div class="relative group">
                <pre class="bg-gray-800 text-gray-100 p-3 rounded text-xs overflow-x-auto font-mono"><%= SetupFirewall.get_manual_command() %></pre>
              </div>
            </div>
          </div>
        </div>

        <!-- Direct Engine Test Section -->
        <div class="bg-white shadow rounded-lg p-6 border-t-4 border-purple-500 md:col-span-2">
          <h2 class="text-xl font-semibold mb-4 flex items-center">
            <.icon name="hero-command-line" class="w-5 h-5 mr-2" /> Direct Engine Test
          </h2>
          <p class="text-sm text-gray-600 mb-4">
            Test the macro engine directly. This bypasses profile configuration and sends a single key tap to the OS.
          </p>
          <div class="flex gap-4">
            <button phx-click="test_tap" phx-value-key="VK_A" class="bg-purple-600 hover:bg-purple-700 text-white font-bold py-2 px-6 rounded transition duration-200 flex items-center">
              Test Tap 'A'
            </button>
            <button phx-click="test_tap" phx-value-key="VK_ENTER" class="bg-purple-600 hover:bg-purple-700 text-white font-bold py-2 px-6 rounded transition duration-200 flex items-center">
              Test Tap 'ENTER'
            </button>
          </div>
        </div>
      </div>

      <div class="mt-8 flex justify-center">
        <%= if match?({:ok, _}, @config_result) do %>
          <a href={~p"/"} class="bg-gray-800 hover:bg-black text-white font-bold py-3 px-10 rounded-full transition duration-200">
            Go to Dashboard
          </a>
        <% else %>
          <div class="text-gray-400 italic">Resolve configuration errors to continue</div>
        <% end %>
      </div>
    </div>
    """
  end
end
