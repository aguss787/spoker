defmodule Spoker.SocketHandler do
  @behaviour :cowboy_websocket

  @vote_type "vote"
  @update_meta_type "update_meta"
  @meta_type "meta"
  @init_type "init"
  @clear_vote_type "clear_vote"
  @kick_type "kick"
  @error_type "error"
  @set_config_type "set_config"
  @config_type "config"

  defmodule State do
    defstruct room_id: "", room: nil, user: nil, ok: true
  end

  def init(request, _state) do
    room_id = request.bindings.room_id

    {:cowboy_websocket, request, %State{room_id: room_id}}
  end

  def websocket_init(state) do
    {:ok, state}
  end

  def websocket_handle({:text, json}, state) do
    payload = Jason.decode!(json)
    type = payload["type"]
    data = payload["data"]

    case type do
      @vote_type -> vote(data, state)
      @init_type -> join_room(data, state)
      @update_meta_type -> update_meta(data, state)
      @clear_vote_type -> clear_vote(data, state)
      @kick_type -> kick(data, state)
      @set_config_type -> set_config(data, state)
    end
    |> Result.map_err(
         fn {reason, state} ->
           Process.send(self(), {:err, reason}, [])
           Result.ok(state)
         end
       )
  end

  defp kick(data, state) do
    Spoker.Room.kick(state.room, state.user, data)
    |> Result.map_raw(fn _ -> state end)
  end

  defp clear_vote(_data, state) do
    Spoker.Room.clear_vote(state.room, state.user)
    |> Result.map_raw(fn _ -> state end)
  end

  defp set_config(data, state) do
    Spoker.Room.set_config(state.room, state.user, data)
    |> Result.map_raw(fn _ -> state end)
  end

  defp update_meta(data, state) do
    title = data["title"]
    description = data["description"]
    Spoker.Room.set_meta(state.room, state.user, title, description)
    |> Result.map_raw(fn _ -> state end)
  end

  defp validate_role(flag, role) do
    Result.map(
      flag,
      fn state ->
        case role do
          :invalid_role -> Result.err({%{type: "auth_error", message: :invalid_role}, state})
          _ -> Result.ok(state)
        end
      end
    )
  end

  defp exchange_token(flag, token) do
    Result.map(
      flag,
      fn state ->
        Spoker.Auth.inspect(token)
        |> Result.map(fn user -> Result.ok(%{state | user: user}) end)
        |> Result.map_err(fn reason -> Result.err({%{type: "auth_error", message: reason}, state}) end)
      end
    )
  end

  defp register_in_room_registry(flag, role) do
    Result.map(
      flag,
      fn state ->
        Spoker.RoomRegistry.join(state.room_id, state.user, role)
        |> Result.map(fn room -> Result.ok(%{state | room: room}) end)
        |> Result.map_err(fn reason -> Result.err({reason, state}) end)
      end
    )
  end

  defp should_ack?(flag) do
    Result.map(
      flag,
      fn state -> {:reply, {:text, Jason.encode!(%{type: @init_type, data: "ack"})}, state} end
    )
  end

  defp join_room(data, state) do
    token = data["token"]
    role = case data["role"] do
      "observer" -> :observer
      "participant" -> :participant
      _ -> :invalid_role
    end

    Result.ok(state)
    |> validate_role(role)
    |> exchange_token(token)
    |> register_in_room_registry(role)
    |> should_ack?()
  end

  defp vote(data, state) do
    Spoker.Room.vote(state.room, state.user, data)
    |> Result.map_raw(fn _ -> state end)
  end

  def websocket_info(:kick, state) do
    Process.send(self(), :stop, [])
    {
      :reply,
      {
        :text,
        Jason.encode!(
          %{
            type: @error_type,
            data: %{
              typed: "kicked",
              message: "kicked"
            }
          }
        )
      },
      state
    }
  end

  def websocket_info({:err, reason}, state) do
    Process.send(self(), :stop, [])
    {:reply, {:text, Jason.encode!(%{type: @error_type, data: reason})}, state}
  end

  def websocket_info(:stop, state) do
    {:stop, state}
  end

  def websocket_info({:meta, meta}, state) do
    {:reply, {:text, Jason.encode!(%{type: @meta_type, data: meta})}, state}
  end

  def websocket_info({:config, config}, state) do
    {:reply, {:text, Jason.encode!(%{type: @config_type, data: config})}, state}
  end

  def websocket_info({:vote, votes, observers, participants}, state) do
    {
      :reply,
      {
        :text,
        Jason.encode!(
          %{
            type: @vote_type,
            data: %{
              votes: votes,
              observers: observers,
              participants: participants
            }
          }
        )
      },
      state
    }
  end

  def websocket_info(message, state) do
    {:reply, {:text, inspect message}, state}
  end
end
