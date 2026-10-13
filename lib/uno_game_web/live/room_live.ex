defmodule UnoGameWeb.RoomLive do
  use UnoGameWeb, :live_view

  alias UnoGame.Rooms

  def mount(%{"id" => room_id} = params, session, socket) do
    # Securely extract the persistent token from the HTTP cookie session
    token = Map.get(session, "session_token")

    # If they came from the join form, the username is in params.
    # If they are reconnecting, it will be nil here, but we will grab it from the GenServer.
    username_param = params["username"]

    # Immediately reject if the room is missing
    if not Rooms.room_exists?(room_id) do
      {:ok, socket |> put_flash(:error, "Room does not exist.") |> redirect(to: "/")}
    else

      if connected?(socket) do
        case Rooms.join_room(room_id, token, username_param) do
          :ok ->
            Phoenix.PubSub.subscribe(UnoGame.PubSub, "room:#{room_id}")
            UnoGameWeb.Presence.track(self(), "presence:room:#{room_id}", token, %{})

            room_state = Rooms.get_room_state(room_id)

            # Safely retrieve the username from the state in case this is a reconnection
            current_username = room_state.players[token].username

            socket =
              socket
              |> assign(:room_id, room_id)
              |> assign(:session_token, token)
              |> assign(:current_user, current_username)
              |> assign(:room_state, room_state)

            {:ok, socket}

          {:error, :room_full} ->
            {:ok, socket |> put_flash(:error, "Room is full.") |> redirect(to: "/")}

          {:error, _reason} ->
            {:ok, socket |> put_flash(:error, "Failed to join room.") |> redirect(to: "/")}
        end
      else
        {:ok, assign(socket, room_id: room_id, session_token: token, current_user: username_param, room_state: nil)}
      end
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto mt-10 p-6 bg-white rounded-lg shadow-md">
      <div class="flex justify-between items-center mb-8 border-b pb-4">
        <h1 class="text-3xl font-bold text-gray-800">Room Code: <span class="text-indigo-600 tracking-widest"><%= @room_id %></span></h1>
        <button phx-click="leave_room" class="px-4 py-2 text-sm text-red-600 border border-red-600 rounded hover:bg-red-50">
          Leave Room
        </button>
      </div>

      <%= if @room_state do %>
        <div class="mb-8">
          <h2 class="text-xl font-semibold mb-4 text-gray-700">Players (<%= map_size(@room_state.players) %>/7)</h2>
          <ul class="space-y-2">
            <%= for {token, player} <- @room_state.players do %>
              <li class="flex items-center justify-between p-3 bg-gray-50 rounded border border-gray-200 text-black">
                <div class="flex items-center">
                  <span class="font-medium"><%= player.username %></span>
                  <%= if @room_state.host == token do %>
                    <span class="ml-2 px-2 py-1 text-xs text-white bg-yellow-500 rounded-full">Host</span>
                  <% end %>
                </div>
                <div>
                  <%= if player.connection_status == :connected do %>
                    <span class="text-sm text-green-600">Connected</span>
                  <% else %>
                    <span class="text-sm text-gray-400">Disconnected</span>
                  <% end %>
                </div>
              </li>
            <% end %>
          </ul>
        </div>

        <%= if @room_state.host == @session_token do %>
          <div class="flex justify-center mt-8">
            <button phx-click="start_game" class="px-8 py-3 text-lg font-bold text-white bg-indigo-600 rounded shadow hover:bg-indigo-700 transition-colors">
              Start Game
            </button>
          </div>
        <% else %>
          <div class="text-center mt-8 text-gray-500 italic">
            Waiting for host to start the game...
          </div>
        <% end %>
      <% else %>
        <div class="text-center py-10 text-gray-500">
          Loading room data...
        </div>
      <% end %>
    </div>
    """
  end

  # Catches the PubSub broadcast from the GenServer
  def handle_info({:state_update, new_state}, socket) do
    {:noreply, assign(socket, :room_state, new_state)}
  end

  def handle_event("leave_room", _params, socket) do
    Rooms.leave_room(socket.assigns.room_id, socket.assigns.session_token)
    {:noreply, redirect(socket, to: "/")}
  end

  def handle_event("start_game", _params, socket) do
    Rooms.start_game(socket.assigns.room_id, socket.assigns.session_token)
    {:noreply, socket}
  end
end
