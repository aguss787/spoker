defmodule Spoker.RoomRegistry do
  use GenServer

  defmodule State do
    defstruct rooms: %{}, refs: %{}
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, %State{}, name: name)
  end

  def reserve(room_id) do
    GenServer.call(__MODULE__, {:reserve, room_id})
  end

  def join(room_id, user, role) do
    Registry.Spoker
    |> Registry.register(room_id, %{user: user})

    GenServer.call(__MODULE__, {:join, room_id})
    |> Result.map(fn room -> set_user_to_room(room, user, role) end)
  end

  defp set_user_to_room(room, user, role) do
    Spoker.Room.set_user(room, user, role)
    |> Result.map_raw(fn _ -> room end)
  end

  ## Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:reserve, room_id}, _from, state) do
    {allocation, state} = if Map.has_key?(state.rooms, room_id) do
      {{:err, %{type: "reserve_room_error", message: :already_exist}}, state}
    else
      room = Spoker.Room.new_room(room_id)
      rooms = Map.put(state.rooms, room_id, room)

      ref = Process.monitor(room)
      refs = Map.put(state.refs, ref, room_id)

      {{:ok, room}, %{rooms: rooms, refs: refs}}
    end

    {:reply, allocation, state}
  end

  @impl true
  def handle_call({:join, room_id}, _from, state) do
    {allocation, state} = if Map.has_key?(state.rooms, room_id) do
      room = Map.fetch!(state.rooms, room_id)
      {{:ok, room}, state}
    else
      {{:err, %{type: "join_room_error", message: :not_exist}}, state}
    end

    {:reply, allocation, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {room_id, refs} = Map.pop(state.refs, ref)
    rooms = Map.delete(state.rooms, room_id)

    {:noreply, %{rooms: rooms, refs: refs}}
  end
end
