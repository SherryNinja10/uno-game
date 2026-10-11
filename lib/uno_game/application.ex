defmodule UnoGame.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      UnoGameWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:uno_game, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: UnoGame.PubSub},
      UnoGameWeb.Presence,

      # Starting a registry for the room genservers
      {Registry, keys: :unique, name: UnoGame.RoomRegistry},

      # starting a dynamic supervisor for room genservers
      {DynamicSupervisor, strategy: :one_for_one, name: UnoGame.RoomSupervisor},

      # Start a worker by calling: UnoGame.Worker.start_link(arg)
      # {UnoGame.Worker, arg},
      # Start to serve requests, typically the last entry
      UnoGameWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: UnoGame.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UnoGameWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
