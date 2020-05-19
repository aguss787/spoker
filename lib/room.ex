defmodule Spoker.Room do
  use GenServer, restart: :temporary

  defmodule State do
    defstruct id: "", title: "T000", description: "", users: %{}, votes: %{}, last_clean_up: nil
  end

  defmodule User do
    defstruct pid: nil, username: "", role: nil
  end

  def new_room(id) do
    {:ok, pid} = DynamicSupervisor.start_child(
      Spoker.RoomSupervisor,
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [id]}
      }
    )
    pid
  end

  def start_link(id) do
    GenServer.start_link(__MODULE__, %State{id: id, last_clean_up: DateTime.utc_now()})
  end

  ## For clients

  def set_user(room, user, role) do
    GenServer.call(room, {:set_user, user, role})
    |> Result.to_result()
  end

  def vote(room, user, value) do
    GenServer.call(room, {:vote, user, value})
    |> Result.to_result()
  end

  def set_meta(room, _user, title, description) do
    GenServer.call(room, {:set_meta, title, description})
    |> Result.to_result()
  end

  def clear_vote(room, _user) do
    GenServer.call(room, {:clear_vote})
    |> Result.to_result()
  end

  def kick(room, _user, target_user) do
    GenServer.call(room, {:kick, target_user})
    |> Result.to_result()
  end

  ## Callbacks

  @impl true
  def init(state) do
    {:ok, state, 1800000}
  end

  @impl true
  def handle_call(message, from, state) do
    state = clean_up(state)
    handle_call_int(message, from, state)
  end

  defp handle_call_int({:set_user, user, role}, {from, _}, state) do
    state = force_clean_up(state)
    if Map.has_key?(state.users, user) && Process.alive?(state.users[user].pid) && state.users[user].pid != from do
      {
        :reply,
        {:err, %{type: "set_user_error", message: :already_exist}},
        state
      }
    else
      users = Map.put(state.users, user, %User{pid: from, username: user, role: role})
      state = %{state | users: users}

      send_votes_to_all(state)
      send_meta(state, from)

      {
        :reply,
        :ok,
        state
      }
    end
  end

  defp handle_call_int({:kick, target_user}, _from, state) do
    {target_user, users} = Map.pop(state.users, target_user)

    state = %{state | users: users}

    state = if target_user != nil do
      if Process.alive?(target_user.pid) do
        Process.send(target_user.pid, :kick, [])
      end

      state = force_clean_up(state)
      send_votes_to_all(state)
      state
    else
      state
    end

    {
      :reply,
      :ok,
      state
    }
  end

  defp handle_call_int({:set_meta, title, description}, {from, _}, state) do
    state = %{
      state
    |
      title: title,
      description: description,
    }

    send_meta_to_all_except_sender(state, from)

    {
      :reply,
      :ok,
      state
    }
  end

  defp handle_call_int({:vote, user, value}, _from, state) do
    votes = Map.put(state.votes, user, value)
    state = %{state | votes: votes}

    send_votes_to_all(state)

    {:reply, :ok, state}
  end

  defp handle_call_int({:clear_vote}, _from, state) do
    state = %{state | votes: %{}}

    send_votes_to_all(state)

    {:reply, :ok, state}
  end

  defp send_meta_to_all_except_sender(state, sender) do
    send_to_all_except_sender(
      state,
      sender,
      fn pid -> send_meta(state, pid) end
    )
  end

  defp send_meta(state, pid) do
    Process.send(pid, {:meta, %{title: state.title, description: state.description}}, [])
  end

  defp send_votes_to_all(state) do
    is_done = Map.keys(state.users)
              |> Enum.filter(fn user -> Map.fetch!(state.users, user).role == :participant end)
              |> Enum.all?(fn user -> Map.has_key?(state.votes, user) end)

    votes = if is_done do
      state.votes
    else
      Map.keys(state.votes)
      |> Enum.reduce(%{}, fn user, acc -> Map.put(acc, user, "?") end)
    end

    observers = Map.keys(state.users)
                |> Enum.filter(fn user -> Map.fetch!(state.users, user).role == :observer end)

    participants = Map.keys(state.users)
                   |> Enum.filter(fn user -> Map.fetch!(state.users, user).role == :participant end)

    send_to_all(state, fn pid -> Process.send(pid, {:vote, votes, observers, participants}, []) end)
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  ## clean up unwanted entry

  defp clean_up(state) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, state.last_clean_up)
    if diff > 15 do
      force_clean_up(state)
    else
      state
    end
  end

  defp force_clean_up(state) do
    state = state
            |> clean_user()
            |> clean_vote()

    %{state | last_clean_up: DateTime.utc_now()}
  end

  defp clean_vote(state) do
    votes = state.users
            |> Map.keys()
            |> Enum.filter(fn key -> Map.has_key?(state.votes, key) end)
            |> Enum.reduce(%{}, fn key, acc -> Map.put(acc, key, state.votes[key]) end)

    %{state | votes: votes}
  end

  defp clean_user(state) do
    users = Registry.Spoker
            |> Registry.lookup(state.id)
            |> Enum.reduce(%{}, fn {_, val}, acc -> Map.put_new(acc, val.user, {}) end)
            |> Map.keys()
            |> Enum.filter(fn key -> Map.has_key?(state.users, key) end)
            |> Enum.reduce(%{}, fn key, acc -> Map.put(acc, key, state.users[key]) end)

    %{state | users: users}
  end

  defp send_to_all(state, f) do
    Registry.Spoker
    |> Registry.dispatch(
         state.id,
         fn (entries) ->
           for {pid, _} <- entries do
             f.(pid)
           end
         end
       )
  end

  defp send_to_all_except_sender(state, sender, f) do
    send_to_all(
      state,
      fn pid ->
        if pid != sender, do: f.(pid)
      end
    )
  end
end
