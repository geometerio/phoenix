defmodule Phoenix.Socket.PoolSupervisor do
  @moduledoc false
  use Supervisor

  # TODO: Use PartitionSupervisor once we require Elixir v1.14
  def start_link({socket_name, config_name, partitions}) do
    IO.puts(" ")
    IO.puts("xxxxxxxxxxxxxxxxx")
    IO.puts("Phoenix.Socket.PoolSupervisor.start_link()....")

    Supervisor.start_link(
      __MODULE__,
      {socket_name, config_name, partitions},
      name: socket_name
    )
  end

  def start_child(endpoint, name, key, spec) do
    case endpoint.config({:socket, name}) do
      ets when not is_nil(ets) ->
        partitions = :ets.lookup_element(ets, :partitions, 2)
        sup = :ets.lookup_element(ets, :erlang.phash2(key, partitions), 2)
        DynamicSupervisor.start_child(sup, spec)

      nil ->
        raise ArgumentError, """
        no socket supervision tree found for #{inspect(name)}.

        Ensure your #{inspect(endpoint)} contains a socket mount, for example:

            socket "/socket", #{inspect(name)},
              websocket: true,
              longpoll: true
        """
    end
  end

  @doc false
  def start_pooled(ref, i) do
    case DynamicSupervisor.start_link(strategy: :one_for_one) do
      {:ok, pid} ->
        :ets.insert(ref, {i, pid})
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def init({socket_name, config_name, partitions}) do
    IO.puts(" ")
    IO.puts("---------------------------------------")
    IO.puts("PoolSupervisor.init()")
    IO.puts("config_name                  : #{config_name}")
    IO.puts("socket_name                  : #{socket_name}")

    ref = :ets.new(config_name, [:public, read_concurrency: true])
    :ets.insert(ref, {:partitions, partitions})
    Phoenix.Config.permanent(config_name, {:socket, socket_name}, ref)

    children =
      for i <- 0..(partitions - 1) do
        %{
          id: i,
          start: {__MODULE__, :start_pooled, [ref, i]},
          type: :supervisor,
          shutdown: :infinity
        }
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
