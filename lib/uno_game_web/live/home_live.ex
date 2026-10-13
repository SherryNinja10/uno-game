defmodule UnoGameWeb.HomeLive do
  use UnoGameWeb, :live_view

  alias UnoGame.Rooms

  def mount(_params, session, socket) do
    # Assign a session token. In a production app, this should be generated
    # via a Plug in the router and passed in through the session map to ensure
    # it persists securely in an HTTP-only cookie to prevent session hijacking.
    session_token = Map.get(session, "session_token")

    # If the user is already in an active room, bypass the home page entirely
    if room_id = Rooms.find_room_by_token(session_token) do
      {:ok, push_navigate(socket, to: "/room/#{room_id}")}
    else
      socket =
        socket
        |> assign(:session_token, session_token)
        |> assign(:username, "")
        |> assign(:error, nil)

      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen bg-gray-100">
      <div class="w-full max-w-md p-8 bg-white rounded-lg shadow-md">
        <h1 class="mb-6 text-3xl font-bold text-center text-gray-800">UNO Platform</h1>

        <%= if @error do %>
          <div class="p-3 mb-4 text-sm text-red-700 bg-red-100 rounded-lg">
            <%= @error %>
          </div>
        <% end %>

        <form phx-change="update_username" phx-submit="create_room" class="space-y-4">
          <div>
            <label for="username" class="block text-sm font-medium text-gray-700">Choose a Username</label>
            <input
              type="text"
              name="username"
              id="username"
              value={@username}
              class="block w-full px-4 py-2 mt-1 text-black border border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
              placeholder="e.g. PlayerOne"
              required
            />
          </div>

          <button
            type="submit"
            class="w-full px-4 py-2 text-white bg-indigo-600 rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
            Create Room
          </button>
        </form>

        <div class="mt-6 border-t border-gray-200 pt-6">
          <form phx-submit="join_room" class="space-y-4">
            <div>
              <label for="room_id" class="block text-sm font-medium text-gray-700">Or Join an Existing Room</label>
              <input
                type="text"
                name="room_id"
                id="room_id"
                class="block w-full px-4 py-2 mt-1 text-black border border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
                placeholder="6-Character Code"
                minlength="6"
                maxlength="6"
                required
              />
            </div>
            <button
              type="submit"
              class="w-full px-4 py-2 text-indigo-700 bg-indigo-100 rounded-md hover:bg-indigo-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
              Join Room
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("create_room", %{"username" => username}, socket) do
    if String.trim(username) == "" do
      {:noreply, assign(socket, :error, "Username cannot be empty.")}
    else
      # Spawns the collision-free GenServer via the context boundary
      case Rooms.create_room() do
        {:ok, room_id} ->
          # Redirect the user to the room route, passing the username as a query parameter
          {:noreply, push_navigate(socket, to: "/room/#{room_id}?username=#{URI.encode(username)}&token=#{socket.assigns.session_token}")}

        {:error, _reason} ->
          {:noreply, assign(socket, :error, "Failed to create room. Please try again.")}
      end
    end
  end

  def handle_event("join_room", %{"room_id" => room_id}, socket) do
    username = socket.assigns.username
    formatted_id = String.trim(room_id)

    cond do
      String.trim(username) == "" ->
        {:noreply, assign(socket, :error, "Please enter a username above before joining.")}

      not Rooms.room_exists?(formatted_id) ->
        {:noreply, assign(socket, :error, "Room does not exist. Please check the code.")}

      true ->
        {:noreply, push_navigate(socket, to: "/room/#{formatted_id}")}
    end
  end

  def handle_event("update_username", %{"username" => username}, socket) do
    {:noreply, assign(socket, :username, username)}
  end
end
