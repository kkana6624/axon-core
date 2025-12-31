defmodule Axon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AxonWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:axon, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Axon.PubSub},
      Axon.App.Execution.MacroLog,
      Axon.App.Execution.SingleRunner,
      Axon.App.Execution.ShutdownPanic,
      Axon.App.Setup.MdnsServer,
      # Start a worker by calling: Axon.Worker.start_link(arg)
      # {Axon.Worker, arg},
      # Start to serve requests, typically the last entry
      AxonWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Axon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AxonWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
