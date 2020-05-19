defmodule Spoker do
  use Application

  def start(_type, _args) do
    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: Spoker.Router,
        options: [
          dispatch: dispatch(),
          port: 8001
        ]
      ),
      Registry.child_spec(
        keys: :duplicate,
        name: Registry.Spoker
      ),
      %{
        id: Spoker.RoomRegistry,
        start: {Spoker.RoomRegistry, :start_link, [Spoker.RoomRegistry]}
      },
      {DynamicSupervisor, strategy: :one_for_one, name: Spoker.RoomSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Spoker.Application]
    Supervisor.start_link(children, opts)
  end

  defp dispatch do
    [
      {:_,
        [
          {"/ws/room/[:room_id]", Spoker.SocketHandler, []},
          {:_, Plug.Cowboy.Handler, {Spoker.Router, []}}
        ]
      }
    ]
  end
end
