defmodule UnoGame.Rooms do
  use GenServer

  alias UnoGame.RoomServer
  alias UnoGame.RoomSupersivor

  def create_room do
    room_id = generate_nano_id()

    # Spawns the process dynamically so it is monitored by your supervisor
    case DynamicSupervisor.start_child(UnoGame.RoomSupervisor, {UnoGame.RoomServer, room_id}) do
      {:ok, _pid} ->
        {:ok, room_id}

      # In the statistically insignificant event of a collision, try again
      {:error, {:already_started, _pid}} ->
        create_room()

      error ->
        error
    end
  end

  def get_room_state(room_id) do
    RoomServer.get_state(room_id)
  end

  @doc """
  Checks if a room exists in the registry.
  """
  def room_exists?(room_id) do
    case Registry.lookup(UnoGame.RoomRegistry, room_id) do
      [{_pid, _value}] -> true
      [] -> false
    end
  end

  def join_room(room_id, session_token, username) do
    RoomServer.join_room(room_id, session_token, username)
  end

  def leave_room(room_id, session_token) do
    RoomServer.leave_room(room_id, session_token)
  end

  @doc """
  Searches all active rooms to find if a session token is currently playing.
  Returns the room_id if found, or nil.
  """
  def find_room_by_token(session_token) do
    # Extract all room_ids currently registered in the unique registry
    room_ids = Registry.select(UnoGame.RoomRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

    Enum.find_value(room_ids, fn room_id ->
      state = get_room_state(room_id)
      if Map.has_key?(state.players, session_token) do
        room_id
      else
        nil
      end
    end)
  end

  def start_game(room_id, host_session_token) do
    RoomServer.start_game(room_id, host_session_token)
  end

  def play_card(room_id, session_token, card) do
    RoomServer.play_card(room_id, session_token, card)
  end

  def draw_card(room_id, session_token) do
    RoomServer.draw_card(room_id, session_token)
  end

  # Generates a fast, URL-safe 6-character string using Erlang's crypto module
  defp generate_nano_id do
    :crypto.strong_rand_bytes(5)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 6)
  end
end
