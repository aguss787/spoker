defmodule Spoker.Router do
  use Plug.Router
  require EEx

  plug CORSPlug
  plug Plug.Static,
       at: "/",
       from: :spoker
  plug :match
  plug Plug.Parsers,
       parsers: [:json],
       pass: ["application/json"],
       json_decoder: Jason
  plug :dispatch

  post "/exchange" do
    auth_code = conn.body_params["auth_code"]
    token = Spoker.Auth.exchange(auth_code)
    case token do
      {:ok, token} -> send_resp(conn, 200, token)
      {:err, code} -> send_resp(conn, code, "Please try again")
    end
  end

  post "/inspect" do
    token = conn.body_params["token"]
    username = Spoker.Auth.inspect(token)
    case username do
      {:ok, username} -> send_resp(conn, 200, username)
      {:err, code} -> send_resp(conn, code, "Please try again")
    end
  end

  post "/reserve" do
    token = get_req_header(conn, "authorization")
    room_id = conn.body_params["room_id"]

    result = {:ok, {}}
    |> with_action(fn _ ->
      case token do
        [token] -> {:ok, token}
        _ -> {:err, {400, :no_auth_token}}
      end
    end)
    |> with_action(fn token ->
      case Spoker.Auth.inspect(token) do
        {:ok, _} -> {:ok, {}}
        {:err, code} -> {:err, {code, :invalid_token}}
      end
    end)
    |> with_action(fn _ ->
      case Spoker.RoomRegistry.reserve(room_id) do
        {:ok, _} -> {:ok, {}}
        {:err, reason} -> {:err, {409, reason}}
      end
    end)

    case result do
      {:ok, _} -> send_resp(conn, 200, "success")
      {:err, {code, reason}} -> send_resp(conn, code, inspect reason)
    end

  end

  match _ do
    send_resp(conn, 404, "404")
  end

  defp with_action({flag, state}, f) do
    case flag do
      :ok -> f.(state)
      _ -> {flag, state}
    end
  end
end
