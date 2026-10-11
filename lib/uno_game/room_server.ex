defmodule UnoGame.RoomServer do
  use GenServer

  alias UnoGame.RoomRegistry

  @max_players 7

  # Formal struct defining the shape of the room state and default values
  defstruct [
    :room_id,                 # String, 6 character NanoID
    host: nil,                # String (session_token of the room creator)
    status: :lobby,           # Atom, :lobby, :playing, :game_over
    players: %{},             # Map, keyed by session_token
    deck: [],                 # List of maps/tuples
    discard_pile: [],         # List of maps/tuples
    current_turn_index: 0,    # Integer
    play_direction: 1,        # Integer (1 for clockwise, -1 for counter-clockwise)
    gc_timer_ref: nil,        # Reference for 30-second garbage collection
    turn_timer_ref: nil       # Reference for Server-Side Dead Man's Switch
  ]

  # Client API now takes just the room_id string to build the via_tuple and initialize state
  def start_link(room_id) when is_binary(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via_tuple(room_id))
  end

  def join_room(room_id, session_token, username) do
    GenServer.call(via_tuple(room_id), {:join_room, session_token, username})
  end

  def start_game(room_id, host_session_token) do
    GenServer.call(via_tuple(room_id), {:start_game, host_session_token})
  end

  def play_card(room_id, session_token, card) do
    GenServer.cast(via_tuple(room_id), {:play_card, session_token, card})
  end

  def draw_card(room_id, session_token) do
    GenServer.cast(via_tuple(room_id), {:draw_card, session_token})
  end

  # Internal helper functions (defp)
  defp via_tuple(room_id) do
    {:via, Registry, {RoomRegistry, room_id}}
  end

  defp broadcast_state(room_state) do
    # Logic to follow
    # e.g., Phoenix.PubSub.broadcast(UnoGame.PubSub, "room:#{room_state.room_id}", {:state_update, room_state})
  end

  defp project_for_player(room_state, session_token) do
    # Logic to follow
  end

  # Server Callbacks
  def init(room_id) do
    # Initialize the struct using the provided room_id and default values
    initial_state = %__MODULE__{room_id: room_id}
    {:ok, initial_state}
  end

  def handle_call({:join_room, session_token, username}, _from, room_state) do
    cond do
      # Case 1: Player is reconnecting
      Map.has_key?(room_state.players, session_token) ->
        updated_players = put_in(room_state.players[session_token].connection_status, :connected)
        new_state = %{room_state | players: updated_players}
        broadcast_state(new_state)
        {:reply, :ok, new_state}

      # Case 2: Room is full (Max 7 players)
      map_size(room_state.players) >= @max_players ->
        {:reply, {:error, :room_full}, room_state}

      # Case 3: New player joining
      true ->
        # Assign as host if this is the first player joining
        new_host = room_state.host || session_token

        new_player = %{
          username: username,
          connection_status: :connected,
          hand: []
        }

        updated_players = Map.put(room_state.players, session_token, new_player)

        new_state = %{room_state | players: updated_players, host: new_host}
        broadcast_state(new_state)

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:start_game, host_session_token}, _from, room_state) do
    # Logic to follow
    {:reply, :ok, room_state}
  end

  def handle_cast({:play_card, session_token, card}, room_state) do
    # Logic to follow
    {:noreply, room_state}
  end

  def handle_cast({:draw_card, session_token}, room_state) do
    # Logic to follow
    {:noreply, room_state}
  end

  def handle_info(:turn_timeout, room_state) do
    # Logic to follow
    {:noreply, room_state}
  end

  def handle_info(:presence_empty, room_state) do
    # Logic to follow
    {:noreply, room_state}
  end

  def handle_info(:execute_gc, room_state) do
    # Logic to follow
    {:noreply, room_state}
  end
end
