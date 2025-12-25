defmodule Axon.App.Execution.SingleRunner do
  @moduledoc false

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_execution(owner_pid, request_id, fun)
      when is_pid(owner_pid) and is_binary(request_id) and request_id != "" and is_function(fun, 0) do
    GenServer.call(__MODULE__, {:start_execution, owner_pid, request_id, fun})
  end

  def panic do
    GenServer.call(__MODULE__, :panic)
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  def try_acquire(owner_pid \\ self()) when is_pid(owner_pid) do
    GenServer.call(__MODULE__, {:try_acquire, owner_pid})
  end

  def release(owner_pid \\ self()) when is_pid(owner_pid) do
    GenServer.call(__MODULE__, {:release, owner_pid})
  end

  @impl true
  def init(_init_arg) do
    {:ok,
     %{
       mode: :idle,
       last_owner: nil,
       last_started_ms: nil,
       owner: nil,
       owner_ref: nil,
       task_pid: nil,
       task_ref: nil,
       request_id: nil
     }}
  end

  @impl true
  def handle_call({:try_acquire, owner_pid}, _from, %{owner: nil} = state) do
    ref = Process.monitor(owner_pid)
    {:reply, :ok, %{state | owner: owner_pid, owner_ref: ref}}
  end

  def handle_call({:try_acquire, _owner_pid}, _from, state) do
    {:reply, :busy, state}
  end

  @impl true
  def handle_call({:start_execution, owner_pid, request_id, fun}, _from, %{mode: :idle, owner: nil} = state) do
    min_interval_ms = Application.get_env(:axon, :tap_macro_min_interval_ms, 100)
    now_ms = System.monotonic_time(:millisecond)

    if owner_pid == state.last_owner and is_integer(state.last_started_ms) and
         is_integer(min_interval_ms) and min_interval_ms >= 0 and
         now_ms - state.last_started_ms < min_interval_ms do
      {:reply, :rate_limited, state}
    else
    owner_ref = Process.monitor(owner_pid)

    {:ok, task_pid} = Task.start(fn -> fun.() end)
    task_ref = Process.monitor(task_pid)

    {:reply, :ok,
     %{
       state
       | mode: :running,
         last_owner: owner_pid,
         last_started_ms: now_ms,
         owner: owner_pid,
         owner_ref: owner_ref,
         task_pid: task_pid,
         task_ref: task_ref,
         request_id: request_id
     }}
    end
  end

  def handle_call({:start_execution, _owner_pid, _request_id, _fun}, _from, %{mode: :panic} = state) do
    {:reply, :panic, state}
  end

  def handle_call({:start_execution, _owner_pid, _request_id, _fun}, _from, state) do
    {:reply, :busy, state}
  end

  @impl true
  def handle_call(:panic, _from, %{task_pid: task_pid, task_ref: task_ref, request_id: request_id} = state)
      when is_pid(task_pid) do
    Process.exit(task_pid, :kill)

    if is_reference(task_ref) do
      Process.demonitor(task_ref, [:flush])
    end

    if is_reference(state.owner_ref) do
      Process.demonitor(state.owner_ref, [:flush])
    end

    {:reply, {:interrupted, request_id}, %{state | mode: :panic, owner: nil, owner_ref: nil, task_pid: nil, task_ref: nil, request_id: nil}}
  end

  def handle_call(:panic, _from, state) do
    {:reply, :idle, %{state | mode: :panic}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok,
     %{
       state
       | mode: :idle,
         last_owner: nil,
         last_started_ms: nil,
         owner: nil,
         owner_ref: nil,
         task_pid: nil,
         task_ref: nil,
         request_id: nil
     }}
  end

  @impl true
  def handle_call({:release, owner_pid}, _from, %{owner: owner_pid, owner_ref: ref} = state)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    if is_reference(state.task_ref) do
      Process.demonitor(state.task_ref, [:flush])
    end

    new_mode = if state.mode == :panic, do: :panic, else: :idle
    {:reply, :ok, %{state | mode: new_mode, owner: nil, owner_ref: nil, task_pid: nil, task_ref: nil, request_id: nil}}
  end

  def handle_call({:release, _owner_pid}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = state)
      when is_reference(ref) do
    if is_reference(state.task_ref) do
      Process.demonitor(state.task_ref, [:flush])
    end

    new_mode = if state.mode == :panic, do: :panic, else: :idle
    {:noreply, %{state | mode: new_mode, owner: nil, owner_ref: nil, task_pid: nil, task_ref: nil, request_id: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task_ref: ref} = state)
      when is_reference(ref) do
    if is_reference(state.owner_ref) do
      Process.demonitor(state.owner_ref, [:flush])
    end

    new_mode = if state.mode == :panic, do: :panic, else: :idle
    {:noreply, %{state | mode: new_mode, owner: nil, owner_ref: nil, task_pid: nil, task_ref: nil, request_id: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
