defmodule UnoGame.RoomServer do
  use GenServer, restart: :transient

  require Logger
  alias UnoGame.RoomRegistry

  @max_players 7

  # Formal struct defining the shape of the room state and default values
  defstruct [
    :room_id,                 # String, 6 character NanoID
    host: nil,                # String (session_token of the room creator)
    status: :lobby,           # Atom, :lobby, :playing, :game_over
    players: %{},             # Map, keyed by session_token
    turn_order: [],           # Add this: List of session_tokens
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

  def leave_room(room_id, session_token) do
    GenServer.call(via_tuple(room_id), {:leave_room, session_token})
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

  def get_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state)
  end

  # Internal helper functions (defp)
  defp via_tuple(room_id) do
    {:via, Registry, {RoomRegistry, room_id}}
  end

  defp broadcast_state(room_state) do
    # Logic to follow
    # e.g., Phoenix.PubSub.broadcast(UnoGame.PubSub, "room:#{room_state.room_id}", {:state_update, room_state})
    Phoenix.PubSub.broadcast(
      UnoGame.PubSub,
      "room:#{room_state.room_id}",
      {:state_update, room_state}
    )
  end

  defp project_for_player(room_state, session_token) do
    # Logic to follow
  end

  # Server Callbacks
  def init(room_id) do
    # Subscribe to the presence topic to monitor active WebSockets
    Phoenix.PubSub.subscribe(UnoGame.PubSub, "presence:room:#{room_id}")

    # Initialize the struct using the provided room_id and default values
    initial_state = %__MODULE__{room_id: room_id}
    {:ok, initial_state}
  end

  def handle_call({:join_room, session_token, username}, _from, room_state) do
    # Cancel the garbage collection timer if someone joins/reconnects
    if room_state.gc_timer_ref do
      Process.cancel_timer(room_state.gc_timer_ref)
    end

    # Strip out the old ref so it is clean for next time
    room_state = %{room_state | gc_timer_ref: nil}

    cond do
      # Case 1: Player is reconnecting (Allowed at any time)
      Map.has_key?(room_state.players, session_token) ->
        new_state = put_in(room_state.players[session_token].connection_status, :connected)
        broadcast_state(new_state)
        {:reply, :ok, new_state}

      # Block new players if the game has already started
      room_state.status != :lobby ->
        {:reply, {:error, :game_in_progress}, room_state}

      # Case 2: Room is full (Max 7 players)
      map_size(room_state.players) >= @max_players ->
        {:reply, {:error, :room_full}, room_state}

      # Case 3: New player joining
      true ->
        new_host = room_state.host || session_token
        new_player = %{username: username, connection_status: :connected, hand: []}
        updated_players = Map.put(room_state.players, session_token, new_player)

        new_state = %{room_state | players: updated_players, host: new_host}
        broadcast_state(new_state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:leave_room, session_token}, _from, room_state) do
    # Remove the player from the map
    updated_players = Map.delete(room_state.players, session_token)

    updated_turn_order = List.delete(room_state.turn_order, session_token)

    if map_size(updated_players) == 0 do
      # If the room is completely empty, terminate immediately without the 30s timer
      new_state = %{room_state | players: updated_players, host: nil}
      {:stop, :normal, :ok, new_state}
    else
      # Reassign host if the leaving player was the current host
      new_host =
        if room_state.host == session_token do
          case Map.keys(updated_players) do
            [next_host_token | _] -> next_host_token # Pick the first available remaining token
            _ -> nil
          end
        else
          room_state.host
        end

      new_index =
        if length(updated_turn_order) > 0 do
          rem(room_state.current_turn_index, length(updated_turn_order))
        else
          0
        end

      new_state = %{
        room_state |
        players: updated_players,
        turn_order: updated_turn_order,
        host: new_host,
        current_turn_index: new_index
      }

      broadcast_state(new_state)
      {:reply, :ok, new_state}
    end
  end

  def handle_call({:start_game, host_session_token}, _from, room_state) do
    if room_state.host == host_session_token and room_state.status == :lobby do
      deck = generate_deck()

      # Randomize seating arrangement based on connected tokens
      turn_order = Enum.shuffle(Map.keys(room_state.players))

      # Deal 7 cards to each player
      {updated_players, remaining_deck} =
        Enum.reduce(room_state.players, {room_state.players, deck}, fn {token, _player}, {acc_players, current_deck} ->
          {hand, rest_deck} = Enum.split(current_deck, 7)
          updated_player = put_in(acc_players[token].hand, hand)
          {updated_player, rest_deck}
        end)

      # Pop the first card for the discard pile
      [first_discard | final_deck] = remaining_deck

      new_state = %{
        room_state |
        status: :playing,
        players: updated_players,
        turn_order: turn_order,
        deck: final_deck,
        discard_pile: [first_discard],
        current_turn_index: 0,
        play_direction: 1
      }

      broadcast_state(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :unauthorized}, room_state}
    end
  end

  def handle_cast({:play_card, session_token, card}, room_state) do
    active_token = Enum.at(room_state.turn_order, room_state.current_turn_index)

    if session_token == active_token do
      top_card = List.first(room_state.discard_pile)

      # 1. Determine the effective color (defaults to standard color if no chosen_color exists)
      effective_top_color = Map.get(top_card, :chosen_color, top_card.color)

      # 2. Validate using the chosen color. If the game starts with a wild (effective_top_color == "black"), anything goes.
      valid_play? =
        effective_top_color == "black" or
        card.color == effective_top_color or
        card.value == top_card.value or
        card.color == "black"

      if valid_play? do
        current_player = room_state.players[session_token]

        # 3. Strip the :chosen_color key so the struct matches exactly what is in the player's hand
        base_card = %{color: card.color, value: card.value}

        # 4. Verify the card actually exists in their hand before committing
        if base_card in current_player.hand do
          updated_hand = current_player.hand -- [base_card]
          updated_current_player = %{current_player | hand: updated_hand}
          players_after_play = Map.put(room_state.players, session_token, updated_current_player)

          new_direction = if card.value == "reverse", do: room_state.play_direction * -1, else: room_state.play_direction
          steps = if card.value in ["skip", "draw2", "wild_draw4"], do: 2, else: 1

          draw_count =
            case card.value do
              "draw2" -> 2
              "wild_draw4" -> 4
              _ -> 0
            end

          player_count = length(room_state.turn_order)

          {final_deck, final_discard, final_players} =
            if draw_count > 0 do
              victim_raw = room_state.current_turn_index + new_direction
              victim_index = rem(victim_raw + player_count, player_count)
              victim_token = Enum.at(room_state.turn_order, victim_index)

              {new_deck, new_discard, drawn_cards} =
                draw_n_cards(room_state.deck, [card | room_state.discard_pile], draw_count)

              victim = players_after_play[victim_token]
              updated_victim = %{victim | hand: victim.hand ++ drawn_cards}

              {new_deck, new_discard, Map.put(players_after_play, victim_token, updated_victim)}
            else
              {room_state.deck, [card | room_state.discard_pile], players_after_play}
            end

          raw_index = room_state.current_turn_index + (new_direction * steps)
          new_index = rem(raw_index + (player_count * steps), player_count)

          new_status = if length(updated_hand) == 0 do
            Process.send_after(self(), :reset_to_lobby, 5000)
            :game_over
          else
            room_state.status
          end

          new_state = %{
            room_state |
            players: final_players,
            deck: final_deck,
            discard_pile: final_discard,
            play_direction: new_direction,
            current_turn_index: new_index,
            status: new_status
          }

          broadcast_state(new_state)
          {:noreply, new_state}
        else
          {:noreply, room_state} # Ignore if they don't have the card
        end
      else
        {:noreply, room_state} # Ignore invalid color/number play
      end
    else
      {:noreply, room_state} # Ignore out-of-turn play
    end
  end

  def handle_cast({:draw_card, session_token}, room_state) do
    active_token = Enum.at(room_state.turn_order, room_state.current_turn_index)

    if session_token == active_token do
      {new_deck, new_discard, drawn_cards} =
        draw_n_cards(room_state.deck, room_state.discard_pile, 1)

      if length(drawn_cards) > 0 do
        current_player = room_state.players[session_token]
        updated_player = %{current_player | hand: current_player.hand ++ drawn_cards}
        updated_players = Map.put(room_state.players, session_token, updated_player)

        player_count = length(room_state.turn_order)
        raw_index = room_state.current_turn_index + room_state.play_direction
        new_index = rem(raw_index + player_count, player_count)

        new_state = %{
          room_state |
          players: updated_players,
          deck: new_deck,
          discard_pile: new_discard,
          current_turn_index: new_index
        }

        broadcast_state(new_state)
        {:noreply, new_state}
      else
        {:noreply, room_state}
      end
    else
      {:noreply, room_state}
    end
  end

  def handle_call(:get_state, _from, room_state) do
    {:reply, room_state, room_state}
  end

  def handle_info(:turn_timeout, room_state) do
    # Logic to follow
    {:noreply, room_state}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, room_state) do
    updated_players =
      Enum.reduce(diff.leaves, room_state.players, fn {token, _meta}, acc ->
        if Map.has_key?(acc, token) do
          put_in(acc[token].connection_status, :disconnected)
        else
          acc
        end
      end)

    # Check if every single player is currently disconnected
    all_disconnected? = Enum.all?(updated_players, fn {_token, player} ->
      player.connection_status == :disconnected
    end)

    # Start the 30-second countdown if empty and no timer currently exists
    new_gc_ref =
      if all_disconnected? and is_nil(room_state.gc_timer_ref) do
        Process.send_after(self(), :execute_gc, 30_000)
      else
        room_state.gc_timer_ref
      end

    new_state = %{room_state | players: updated_players, gc_timer_ref: new_gc_ref}
    broadcast_state(new_state)

    {:noreply, new_state}
  end

  def handle_info(:presence_empty, room_state) do
    # Logic to follow
    {:noreply, room_state}
  end

  def handle_info(:execute_gc, room_state) do
    # Returning :stop with :normal reason cleanly terminates the GenServer
    {:stop, :normal, room_state}
  end

  def handle_info(:reset_to_lobby, room_state) do
    # Clear all hands for the next game
    reset_players =
      Enum.reduce(room_state.players, %{}, fn {token, player}, acc ->
        Map.put(acc, token, %{player | hand: []})
      end)

    new_state = %{
      room_state |
      status: :lobby,
      players: reset_players,
      deck: [],
      discard_pile: [],
      turn_order: [],
      current_turn_index: 0,
      play_direction: 1
    }

    broadcast_state(new_state)
    {:noreply, new_state}
  end

  def terminate(reason, room_state) do
    Logger.info("Room #{room_state.room_id} has been terminated. Reason: #{inspect(reason)}")
    :ok
  end

  defp generate_deck do
    colors = ["red", "blue", "green", "yellow"]
    values = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "skip", "reverse", "draw2"]
    wilds = ["wild", "wild_draw4"]

    colored_cards =
      for color <- colors, value <- values do
        count = if value == "0", do: 1, else: 2
        List.duplicate(%{color: color, value: value}, count)
      end
      |> List.flatten()

    wild_cards =
      for wild <- wilds do
        List.duplicate(%{color: "black", value: wild}, 4)
      end
      |> List.flatten()

    Enum.shuffle(colored_cards ++ wild_cards)
  end

  defp draw_n_cards(deck, discard, count, drawn \\ [])

  # Base case: we have drawn the requested number of cards
  defp draw_n_cards(deck, discard, 0, drawn), do: {deck, discard, Enum.reverse(drawn)}

  # Case: Deck is empty, but we still need to draw. Reshuffle the discard pile.
  defp draw_n_cards([], [top_discard | rest_discard], count, drawn) do
    reshuffled_deck = Enum.shuffle(rest_discard)
    draw_n_cards(reshuffled_deck, [top_discard], count, drawn)
  end

  # Case: Deck has cards. Pop one and recurse.
  defp draw_n_cards([card | rest_deck], discard, count, drawn) do
    draw_n_cards(rest_deck, discard, count - 1, [card | drawn])
  end

  # Edge case fallback: Every single card is in players' hands, stop drawing
  defp draw_n_cards([], discard, _count, drawn), do: {[], discard, Enum.reverse(drawn)}
end
