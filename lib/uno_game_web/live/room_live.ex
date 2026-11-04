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
              |> assign(:pending_wild, nil)
              |> assign(:time_remaining, 30)
              |> assign(:timer_ref, nil)

            {:ok, socket}

          {:error, :room_full} ->
            {:ok, socket |> put_flash(:error, "Room is full.") |> redirect(to: "/")}

          {:error, _reason} ->
            {:ok, socket |> put_flash(:error, "Failed to join room.") |> redirect(to: "/")}
        end
      else
        {:ok, assign(socket, room_id: room_id, session_token: token, current_user: username_param, room_state: nil, time_remaining: 30, timer_ref: nil)}
      end
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 flex flex-col relative">
      <%= if @room_state do %>

        <!-- LOBBY STATE -->
        <%= if @room_state.status == :lobby do %>
          <div class="max-w-4xl mx-auto mt-10 p-6 bg-white rounded-lg shadow-md w-full">
            <div class="flex justify-between items-center mb-8 border-b pb-4">
              <h1 class="text-3xl font-bold text-gray-800">Room Code: <span class="text-indigo-600 tracking-widest"><%= @room_id %></span></h1>
              <button phx-click="leave_room" class="px-4 py-2 text-sm text-red-600 border border-red-600 rounded hover:bg-red-50">
                Leave Room
              </button>
            </div>

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
          </div>
        <% end %>

        <!-- GAME OVER STATE -->
        <%= if @room_state.status == :game_over do %>
          <% winner_tuple = Enum.find(@room_state.players, fn {_token, p} -> length(p.hand) == 0 end) %>
          <% {_, winner} = winner_tuple || {nil, %{username: "Someone"}} %>

          <div class="flex-grow flex flex-col items-center justify-center bg-gray-900 text-white p-6 relative overflow-hidden">
            <!-- Confetti/Celebration effect placeholder -->
            <div class="absolute inset-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-yellow-500/20 via-gray-900 to-gray-900"></div>

            <div class="z-10 flex flex-col items-center animate-bounce-short">
              <span class="text-6xl mb-4">🏆</span>
              <h1 class="text-6xl font-black text-transparent bg-clip-text bg-gradient-to-r from-yellow-400 to-yellow-600 mb-2 uppercase tracking-widest text-center">
                <%= winner.username %> Wins!
              </h1>
              <p class="text-xl text-gray-400 font-bold tracking-widest mt-8 animate-pulse">
                Returning to lobby in 5 seconds...
              </p>
            </div>
          </div>
        <% end %>

        <!-- PLAYING STATE -->
        <%= if @room_state.status == :playing do %>
          <% current_player = @room_state.players[@session_token] %>
          <% top_card = List.first(@room_state.discard_pile) %>

          <!-- Extract opponents in seating order, skipping the current user -->
          <% opponents_in_order =
               @room_state.turn_order
               |> Enum.reject(&(&1 == @session_token))
               |> Enum.map(&{&1, @room_state.players[&1]})
          %>

          <!-- Turn Management Logic -->
          <% player_count = length(@room_state.turn_order) %>
          <% current_idx = @room_state.current_turn_index %>
          <% dir = @room_state.play_direction %>

          <% active_token = Enum.at(@room_state.turn_order, current_idx) %>
          <% my_turn? = active_token == @session_token %>

          <!-- Determine Next and Previous indices using safe modulo math -->
          <% next_idx = rem(current_idx + dir + player_count, player_count) %>
          <% prev_idx = rem(current_idx - dir + player_count, player_count) %>

          <% next_token = Enum.at(@room_state.turn_order, next_idx) %>
          <% prev_token = Enum.at(@room_state.turn_order, prev_idx) %>

          <!-- Top: Opponents & Timer -->
          <div class="flex-none p-4 bg-white shadow flex items-center justify-between relative overflow-x-auto">
            <div class="flex-1 flex justify-center space-x-8 min-w-max">
              <%= for {opp_token, opponent} <- opponents_in_order do %>
                <% is_active = opp_token == active_token %>
                <% is_next = opp_token == next_token %>
                <% is_prev = opp_token == prev_token %>

                <div class={[
                  "flex flex-col items-center p-2 rounded-lg transition-all duration-300 border-2 relative",
                  is_active && "border-yellow-400 bg-yellow-50 scale-110 shadow-md",
                  is_next && "border-blue-400 bg-blue-50",
                  is_prev && "border-gray-300 opacity-75",
                  !is_active && !is_next && !is_prev && "border-transparent hover:bg-gray-50"
                ]}>

                  <%= if is_next do %>
                    <div class="absolute -top-3 bg-blue-500 text-white text-[10px] font-black px-2 py-0.5 rounded-full shadow-sm tracking-wider">NEXT</div>
                  <% end %>
                  <%= if is_prev do %>
                    <div class="absolute -top-3 bg-gray-400 text-white text-[10px] font-black px-2 py-0.5 rounded-full shadow-sm tracking-wider">PREV</div>
                  <% end %>

                  <!-- Catch button overlay -->
                  <%= if length(opponent.hand) == 1 and not Map.get(opponent, :called_uno, false) do %>
                    <button phx-click="catch_uno" phx-value-target={opp_token} class="absolute -bottom-4 z-20 bg-red-600 hover:bg-red-500 text-white text-[11px] font-black px-3 py-1 rounded-full shadow-lg border border-white animate-bounce">
                      CATCH!
                    </button>
                  <% end %>

                  <span class={[
                    "font-bold transition-colors",
                    is_active && "text-2xl text-yellow-700",
                    is_next && "text-xl text-blue-700",
                    (!is_active && !is_next) && "text-xl text-gray-800"
                  ]}><%= opponent.username %></span>

                  <span class={[
                    "text-sm font-semibold px-3 py-1 rounded-full mt-1 transition-colors",
                    is_active && "text-yellow-800 bg-yellow-200",
                    is_next && "text-blue-800 bg-blue-200",
                    (!is_active && !is_next) && "text-gray-500 bg-gray-200"
                  ]}>
                    <%= length(opponent.hand) %> Cards
                  </span>
                </div>
              <% end %>
            </div>

            <!-- Timer -->
            <div class="absolute right-8 top-4 flex flex-col items-end">
              <span class="text-xs font-bold text-gray-400 uppercase tracking-wider mb-1">Time Remaining</span>
              <div class={["px-4 py-2 rounded shadow text-2xl font-mono font-bold", @time_remaining <= 5 && "bg-red-900 text-red-400 animate-pulse", @time_remaining > 5 && "bg-gray-800 text-white"]}>
                00:<%= String.pad_leading(Integer.to_string(@time_remaining), 2, "0") %>
              </div>
            </div>
          </div>

          <!-- Middle: Play Area (Draw & Discard) -->
          <div class="flex-grow flex items-center justify-center space-x-16 bg-green-800 shadow-inner relative">

            <!-- Play Direction Indicator -->
            <div class="absolute top-6 left-1/2 transform -translate-x-1/2 bg-black/40 border border-white/20 text-white/90 px-6 py-2 rounded-full text-sm font-black tracking-widest flex items-center shadow-lg">
              <%= if @room_state.play_direction == 1 do %>
                <span class="mr-2 animate-pulse">➡️</span> CLOCKWISE <span class="ml-2 animate-pulse">➡️</span>
              <% else %>
                <span class="mr-2 animate-pulse">⬅️</span> COUNTER-CLOCKWISE <span class="ml-2 animate-pulse">⬅️</span>
              <% end %>
            </div>

            <!-- Draw Pile -->
            <div class="flex flex-col items-center cursor-pointer hover:-translate-y-2 transition-transform" phx-click="draw_card">
              <div class="w-32 h-48 bg-gray-900 rounded-xl border-4 border-white shadow-xl flex items-center justify-center relative overflow-hidden">
                <div class="w-24 h-40 border-2 border-red-500 rounded-lg flex items-center justify-center rotate-[-20deg]">
                   <span class="text-white font-black text-4xl italic">UNO</span>
                </div>
              </div>
              <span class="mt-4 text-white font-bold tracking-widest bg-black/30 px-4 py-1 rounded">DRAW</span>
            </div>

            <!-- Discard Pile -->
            <div class="flex flex-col items-center relative">
              <%= if top_card do %>
                <UnoGameWeb.CardComponents.uno_card color={top_card.color} value={top_card.value} class="hover:-translate-y-0" />

                <!-- Chosen Color Badge -->
                <%= if Map.has_key?(top_card, :chosen_color) do %>
                  <% badge_color = case top_card.chosen_color do
                       "red" -> "bg-red-500"
                       "blue" -> "bg-blue-500"
                       "green" -> "bg-green-500"
                       "yellow" -> "bg-yellow-500"
                       _ -> "bg-gray-800"
                     end %>
                  <div class={"absolute -top-4 z-20 px-4 py-1 rounded-full border-2 border-white text-white font-bold text-sm shadow-lg tracking-widest uppercase #{badge_color}"}>
                    <%= top_card.chosen_color %>
                  </div>
                <% end %>

              <% else %>
                <div class="w-32 h-48 border-4 border-dashed border-white/30 rounded-xl flex items-center justify-center">
                  <span class="text-white/50 font-bold">EMPTY</span>
                </div>
              <% end %>
              <span class="mt-4 text-white font-bold tracking-widest bg-black/30 px-4 py-1 rounded">DISCARD</span>
            </div>
          </div>

          <!-- Bottom: Current Player Hand -->
          <div class="flex-none p-6 bg-gray-900 text-white flex flex-col items-center shadow-[0_-10px_20px_rgba(0,0,0,0.3)] relative z-10">
            <div class="mb-4 w-full max-w-6xl flex justify-between items-end">
              <div class="text-2xl font-bold flex items-center space-x-3">
                <span class="bg-indigo-600 px-4 py-1 rounded-full"><%= current_player.username %></span>

                <!-- UNO Call Button -->
                <%= if length(current_player.hand) <= 2 do %>
                  <button phx-click="call_uno" disabled={Map.get(current_player, :called_uno, false)} class={["ml-4 px-4 py-1 rounded-full font-black tracking-widest text-sm border-2 transition-all", Map.get(current_player, :called_uno, false) && "bg-green-600 border-green-400 text-white opacity-50 cursor-not-allowed", not Map.get(current_player, :called_uno, false) && "bg-red-600 border-white text-white shadow-lg hover:scale-110 hover:bg-red-500 animate-pulse"]}>
                    <%= if Map.get(current_player, :called_uno, false), do: "SAFE", else: "UNO!" %>
                  </button>
                <% end %>

                <%= if my_turn? do %>
                  <span class="text-yellow-400 text-lg animate-pulse ml-4">⭐ Your Turn</span>
                <% else %>
                  <span class="text-gray-500 text-sm italic ml-4">Waiting for other players...</span>
                <% end %>
              </div>

              <button phx-click="leave_room" class="text-sm text-red-400 hover:text-red-300 underline">
                Leave Game
              </button>
            </div>

            <!-- Overlapping Cards -->
            <div class="flex space-x-[-3rem] overflow-x-auto py-4 px-12 max-w-full min-h-[14rem]">
              <%= for card <- current_player.hand do %>
                <% click_event = if my_turn?, do: (if card.color == "black", do: "select_wild", else: "play_card"), else: nil %>
                <div phx-click={click_event} phx-value-color={card.color} phx-value-value={card.value}>
                  <UnoGameWeb.CardComponents.uno_card
                    color={card.color}
                    value={card.value}
                    class={["transform transition-all duration-200", my_turn? && "hover:z-10 focus:z-10 cursor-pointer hover:-translate-y-6", !my_turn? && "cursor-not-allowed opacity-80"]}
                  />
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

      <% else %>
        <div class="flex items-center justify-center h-screen text-gray-500 font-bold text-xl">
          Loading game state...
        </div>
      <% end %>

      <!-- Color Picker Modal -->
      <%= if assigns[:pending_wild] do %>
        <div class="absolute inset-0 bg-black/75 z-50 flex items-center justify-center backdrop-blur-sm">
          <div class="bg-white p-8 rounded-2xl shadow-2xl flex flex-col items-center border-4 border-gray-200">
            <h3 class="text-3xl font-black mb-6 text-gray-800 tracking-wider">CHOOSE A COLOR</h3>
            <div class="grid grid-cols-2 gap-4 mb-8">
              <button phx-click="play_wild" phx-value-color="red" class="w-32 h-32 bg-red-500 rounded-xl hover:scale-105 transition-transform shadow-inner border-4 border-red-600"></button>
              <button phx-click="play_wild" phx-value-color="blue" class="w-32 h-32 bg-blue-500 rounded-xl hover:scale-105 transition-transform shadow-inner border-4 border-blue-600"></button>
              <button phx-click="play_wild" phx-value-color="green" class="w-32 h-32 bg-green-500 rounded-xl hover:scale-105 transition-transform shadow-inner border-4 border-green-600"></button>
              <button phx-click="play_wild" phx-value-color="yellow" class="w-32 h-32 bg-yellow-500 rounded-xl hover:scale-105 transition-transform shadow-inner border-4 border-yellow-600"></button>
            </div>
            <button phx-click="cancel_wild" class="text-gray-500 hover:text-gray-800 font-bold underline transition-colors">Cancel Play</button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Catches the PubSub broadcast from the GenServer
  def handle_info({:state_update, new_state}, socket) do
    old_state = socket.assigns.room_state
    is_playing = new_state.status == :playing

    turn_changed? =
      old_state == nil or
      old_state.current_turn_index != new_state.current_turn_index or
      old_state.status != new_state.status

    socket = assign(socket, :room_state, new_state)

    socket =
      if is_playing and turn_changed? do
        if socket.assigns[:timer_ref], do: Process.cancel_timer(socket.assigns.timer_ref)
        ref = Process.send_after(self(), :tick, 1000)

        socket
        |> assign(:time_remaining, 30)
        |> assign(:timer_ref, ref)
      else
        # Stop ticking if the game ended
        if not is_playing and socket.assigns[:timer_ref] do
          Process.cancel_timer(socket.assigns.timer_ref)
          socket |> assign(:timer_ref, nil) |> assign(:time_remaining, 30)
        else
          socket
        end
      end

    {:noreply, socket}
  end

  # Local LiveView tick loop to update the UI every second
  def handle_info(:tick, socket) do
    time_remaining = max(0, socket.assigns.time_remaining - 1)

    ref =
      if time_remaining > 0 do
        Process.send_after(self(), :tick, 1000)
      else
        nil
      end

    {:noreply, socket |> assign(:time_remaining, time_remaining) |> assign(:timer_ref, ref)}
  end

  def handle_event("leave_room", _params, socket) do
    Rooms.leave_room(socket.assigns.room_id, socket.assigns.session_token)
    {:noreply, redirect(socket, to: "/")}
  end

  def handle_event("start_game", _params, socket) do
    Rooms.start_game(socket.assigns.room_id, socket.assigns.session_token)
    {:noreply, socket}
  end

  def handle_event("play_card", %{"color" => color, "value" => value}, socket) do
    # Reconstruct the card map using atom keys to match the GenServer deck structure
    card = %{color: color, value: value}
    Rooms.play_card(socket.assigns.room_id, socket.assigns.session_token, card)

    {:noreply, socket}
  end

  def handle_event("draw_card", _params, socket) do
    Rooms.draw_card(socket.assigns.room_id, socket.assigns.session_token)
    {:noreply, socket}
  end

  def handle_event("select_wild", %{"value" => value}, socket) do
    {:noreply, assign(socket, :pending_wild, value)}
  end

  def handle_event("cancel_wild", _params, socket) do
    {:noreply, assign(socket, :pending_wild, nil)}
  end

  def handle_event("play_wild", %{"color" => chosen_color}, socket) do
    # Bundle the selected color into the card payload
    card = %{color: "black", value: socket.assigns.pending_wild, chosen_color: chosen_color}
    Rooms.play_card(socket.assigns.room_id, socket.assigns.session_token, card)

    {:noreply, assign(socket, :pending_wild, nil)}
  end

  def handle_event("call_uno", _params, socket) do
    Rooms.call_uno(socket.assigns.room_id, socket.assigns.session_token)
    {:noreply, socket}
  end

  def handle_event("catch_uno", %{"target" => target_token}, socket) do
    Rooms.catch_uno(socket.assigns.room_id, socket.assigns.session_token, target_token)
    {:noreply, socket}
  end
end
