defmodule UnoGame.Rooms do
  use GenServer

  alias UnoGame.RoomServer
  alias UnoGame.RoomSupersivor

  def create_room(room_id) do
    room_id = generate_nano_id()

    # Spawns the process dynamically so it is monitored by your supervisor
    case DynamicSupervisor.start_child(RoomSupervisor, {RoomServer, room_id}) do
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

  def join_room(room_id, session_token, username) do
    RoomServer.join_room(room_id, session_token, username)
  end

  def leave_room(room_id, session_token) do
    RoomServer.leave_room(room_id, session_token)
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
