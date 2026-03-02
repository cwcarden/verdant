defmodule VerdantWeb.LockLive do
  use VerdantWeb, :live_view

  @token_salt "pin_unlock"

  def mount(_params, session, socket) do
    pin_code = Verdant.Settings.get("pin_code", "")
    return_to = Map.get(session, "return_to", "/")
    email_to = Verdant.Settings.get("email_to", "")

    {:ok,
     socket
     |> assign(:page_title, "Verdant — Locked")
     |> assign(:pin_length, String.length(pin_code))
     |> assign(:return_to, return_to)
     |> assign(:digits, [])
     |> assign(:error, nil)
     |> assign(:shake, false)
     |> assign(:recovery_sent, false)
     |> assign(:email_configured, email_to != "")}
  end

  def handle_event("digit", %{"n" => n}, socket) do
    digits = socket.assigns.digits

    if length(digits) < socket.assigns.pin_length do
      new_digits = digits ++ [n]

      if length(new_digits) == socket.assigns.pin_length do
        verify(socket, new_digits)
      else
        {:noreply, assign(socket, digits: new_digits, error: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("backspace", _params, socket) do
    new_digits =
      case socket.assigns.digits do
        [] -> []
        digits -> Enum.drop(digits, -1)
      end

    {:noreply, assign(socket, digits: new_digits, error: nil)}
  end

  def handle_event("forgot_pin", _params, socket) do
    case Verdant.Notifier.send_passcode_recovery() do
      {:ok, :sent} ->
        {:noreply, assign(socket, recovery_sent: true, error: nil)}

      {:error, :no_pin_set} ->
        {:noreply, assign(socket, error: "No passcode is set")}

      {:error, :not_configured} ->
        {:noreply, assign(socket, error: "Email not configured — set SMTP settings first")}

      {:error, _} ->
        {:noreply, assign(socket, error: "Could not send recovery email")}
    end
  end

  def handle_info(:clear_shake, socket) do
    {:noreply, assign(socket, shake: false)}
  end

  defp verify(socket, digits) do
    entered = Enum.join(digits)
    stored = Verdant.Settings.get("pin_code", "")

    if entered == stored do
      token = Phoenix.Token.sign(VerdantWeb.Endpoint, @token_salt, :verified)
      return_to = URI.encode(socket.assigns.return_to)

      {:noreply,
       push_navigate(socket, to: "/session/unlock?token=#{token}&return_to=#{return_to}")}
    else
      Process.send_after(self(), :clear_shake, 600)

      {:noreply,
       assign(socket,
         digits: [],
         error: "Incorrect passcode",
         shake: true
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/15 via-base-200 to-base-300 px-4">
      <div class="w-full max-w-xs">
        <%!-- Card --%>
        <div class="card bg-base-100 shadow-2xl border border-base-300/50">
          <div class="card-body items-center text-center p-8 gap-6">
            <%!-- Brand --%>
            <div class="flex flex-col items-center gap-2">
              <div class="bg-primary rounded-2xl p-4 shadow-lg">
                <.icon name="hero-sparkles" class="size-8 text-primary-content" />
              </div>
              <div>
                <h1 class="text-2xl font-bold tracking-tight">Verdant</h1>
                <p class="text-xs text-base-content/50 mt-0.5">Smart Irrigation</p>
              </div>
            </div>

            <%!-- Dot indicators --%>
            <div class="flex flex-col items-center gap-3">
              <div
                id="pin-dots"
                class={["flex gap-3", if(@shake, do: "animate-shake")]}
              >
                <%!-- //1 forces ascending step — prevents 1..0 generating [1,0] in Elixir --%>
                <%= for i <- 1..@pin_length//1 do %>
                  <div class={[
                    "rounded-full size-4 transition-all duration-150",
                    if(i <= length(@digits),
                      do: "bg-primary scale-110",
                      else: "bg-base-300"
                    )
                  ]} />
                <% end %>
              </div>
              <%= if @recovery_sent do %>
                <p class="text-success text-sm font-medium">
                  ✓ Passcode sent to your email
                </p>
              <% else %>
                <%= if @error do %>
                  <p class="text-error text-sm font-medium">{@error}</p>
                <% else %>
                  <p class="text-base-content/50 text-sm">Enter passcode</p>
                <% end %>
              <% end %>
            </div>

            <%!-- Numeric keypad --%>
            <div class="grid grid-cols-3 gap-2 w-full">
              <%!-- Row 1: 1 2 3 --%>
              <%= for n <- ["1", "2", "3"] do %>
                <button
                  type="button"
                  phx-click="digit"
                  phx-value-n={n}
                  class="btn btn-ghost text-2xl font-light h-16 rounded-2xl hover:bg-primary/10 active:scale-95 transition-transform"
                >
                  {n}
                </button>
              <% end %>

              <%!-- Row 2: 4 5 6 --%>
              <%= for n <- ["4", "5", "6"] do %>
                <button
                  type="button"
                  phx-click="digit"
                  phx-value-n={n}
                  class="btn btn-ghost text-2xl font-light h-16 rounded-2xl hover:bg-primary/10 active:scale-95 transition-transform"
                >
                  {n}
                </button>
              <% end %>

              <%!-- Row 3: 7 8 9 --%>
              <%= for n <- ["7", "8", "9"] do %>
                <button
                  type="button"
                  phx-click="digit"
                  phx-value-n={n}
                  class="btn btn-ghost text-2xl font-light h-16 rounded-2xl hover:bg-primary/10 active:scale-95 transition-transform"
                >
                  {n}
                </button>
              <% end %>

              <%!-- Row 4: blank, 0, backspace --%>
              <div />
              <button
                type="button"
                phx-click="digit"
                phx-value-n="0"
                class="btn btn-ghost text-2xl font-light h-16 rounded-2xl hover:bg-primary/10 active:scale-95 transition-transform"
              >
                0
              </button>
              <button
                type="button"
                phx-click="backspace"
                class="btn btn-ghost h-16 rounded-2xl hover:bg-base-300 active:scale-95 transition-transform"
              >
                <.icon name="hero-backspace" class="size-6 text-base-content/60" />
              </button>
            </div>

            <%!-- Forgot passcode link (only when email is configured) --%>
            <%= if @email_configured and not @recovery_sent do %>
              <button
                type="button"
                phx-click="forgot_pin"
                class="text-xs text-base-content/40 hover:text-base-content/70 underline underline-offset-2 transition-colors"
              >
                Forgot passcode? Email it to me
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Footer --%>
        <p class="text-center text-xs text-base-content/30 mt-6">
          Verdant Irrigation System
        </p>
      </div>
    </div>

    <style>
      @keyframes shake {
        0%, 100% { transform: translateX(0); }
        15% { transform: translateX(-6px); }
        30% { transform: translateX(6px); }
        45% { transform: translateX(-5px); }
        60% { transform: translateX(5px); }
        75% { transform: translateX(-3px); }
        90% { transform: translateX(3px); }
      }
      .animate-shake {
        animation: shake 0.55s cubic-bezier(.36,.07,.19,.97) both;
      }
    </style>
    """
  end
end
