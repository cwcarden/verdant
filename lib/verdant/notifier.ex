defmodule Verdant.Notifier do
  @moduledoc """
  GenServer that listens to irrigation PubSub events and sends email
  notifications based on the per-event settings configured by the user.

  Notification settings (all default false except skipped):
    notify_schedule_start    – first zone of a scheduled run begins
    notify_schedule_complete – an entire schedule finishes
    notify_schedule_skipped  – a schedule is skipped due to weather
    notify_manual_start      – a manually-triggered zone starts
    notify_manual_stop       – a manually-triggered zone is stopped

  SMTP credentials are read from Settings at send-time so changes take
  effect without restarting the app.
  """

  use GenServer
  require Logger

  alias Verdant.{Settings, LocalTime}

  @topic "irrigation"
  @pubsub Verdant.PubSub

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
    # Track which schedules are currently mid-run so we only send "started"
    # once per schedule (not once per zone).
    {:ok, %{running_schedules: MapSet.new()}}
  end

  # ── Event handlers ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:watering_started, info}, state) do
    state =
      case info.trigger do
        "schedule" ->
          if MapSet.member?(state.running_schedules, info.schedule_name) do
            # Not the first zone – skip "started" notification
            state
          else
            if Settings.get_bool("notify_schedule_start") do
              send_email(
                "Watering schedule started – #{info.schedule_name}",
                """
                Your irrigation schedule has started.

                Schedule: #{info.schedule_name}
                First zone: #{info.zone_name}
                Planned runtime: #{div(info.planned_seconds || 0, 60)} min
                Started at: #{format_time(info.started_at)}
                #{if info.queue_length > 0, do: "Zones remaining in queue: #{info.queue_length}", else: ""}

                — Verdant Irrigation
                """
              )
            end

            %{state | running_schedules: MapSet.put(state.running_schedules, info.schedule_name)}
          end

        "manual" ->
          if Settings.get_bool("notify_manual_start") do
            send_email(
              "Manual watering started – #{info.zone_name}",
              """
              A zone has been started manually.

              Zone: #{info.zone_name}
              Planned runtime: #{div(info.planned_seconds || 0, 60)} min
              Started at: #{format_time(info.started_at)}

              — Verdant Irrigation
              """
            )
          end

          state

        _ ->
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:schedule_complete, %{schedule_name: name}}, state) do
    if Settings.get_bool("notify_schedule_complete") do
      send_email(
        "Watering schedule complete – #{name}",
        """
        Your irrigation schedule has finished successfully.

        Schedule: #{name}
        Completed at: #{format_now()}

        — Verdant Irrigation
        """
      )
    end

    {:noreply, %{state | running_schedules: MapSet.delete(state.running_schedules, name)}}
  end

  @impl true
  def handle_info({:watering_stopped, %{reason: :manual, zone_name: zone_name, actual_seconds: secs}}, state) do
    if Settings.get_bool("notify_manual_stop") do
      send_email(
        "Manual watering stopped – #{zone_name}",
        """
        A manually-started zone has been stopped.

        Zone: #{zone_name}
        Actual runtime: #{div(secs || 0, 60)}m #{rem(secs || 0, 60)}s
        Stopped at: #{format_now()}

        — Verdant Irrigation
        """
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:schedule_skipped, %{schedule_name: name, reason: reason}}, state) do
    if Settings.get_bool("notify_schedule_skipped") do
      send_email(
        "Watering skipped – #{name}",
        """
        A scheduled watering was skipped due to current weather conditions.

        Schedule: #{name}
        Reason: #{format_skip_reason(reason)}
        Time: #{format_now()}

        Adjust your weather thresholds in Settings → Watering Skip Conditions
        if you'd like to change this behaviour.

        — Verdant Irrigation
        """
      )
    end

    {:noreply, state}
  end

  # Ignore other PubSub messages
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Public API ────────────────────────────────────────────────────────────────

  @doc "Send a one-off test email using the current SMTP settings (ignores notifications_enabled flag)."
  def test_email do
    # 30 s – SMTP handshake can be slow on first connect
    GenServer.call(__MODULE__, :test_email, 30_000)
  end

  @doc """
  Send the current PIN passcode to the configured email address.
  Used as a recovery option from the lock screen.
  Ignores notifications_enabled — always sends if SMTP is configured.
  """
  def send_passcode_recovery do
    GenServer.call(__MODULE__, :send_passcode_recovery, 30_000)
  end

  @impl true
  def handle_call(:test_email, _from, state) do
    result =
      do_deliver(
        "Test email – Verdant Notifications are working!",
        """
        This is a test email from your Verdant irrigation system.

        If you received this, your SMTP settings are configured correctly.

        Sent at: #{LocalTime.format(DateTime.utc_now())}

        — Verdant Irrigation
        """
      )

    {:reply, result, state}
  end

  @impl true
  def handle_call(:send_passcode_recovery, _from, state) do
    pin = Settings.get("pin_code", "")

    result =
      if pin == "" do
        {:error, :no_pin_set}
      else
        do_deliver(
          "Verdant Passcode Recovery",
          """
          A passcode recovery was requested from your Verdant lock screen.

          Passcode: #{pin}
          Requested at: #{LocalTime.format(DateTime.utc_now())}

          If you did not request this, someone may be at your irrigation controller.

          — Verdant Irrigation
          """
        )
      end

    {:reply, result, state}
  end

  # ── Email helpers ─────────────────────────────────────────────────────────────

  # Checks notifications_enabled before sending; fire-and-forget (no return value used).
  defp send_email(subject, body) do
    if Settings.get_bool("notifications_enabled", false) do
      do_deliver(subject, body)
    end

    :ok
  end

  # Direct SSL SMTP implementation – mirrors Python's smtplib.SMTP_SSL + login().
  # Bypasses gen_smtp/Swoosh entirely to avoid their OTP 25+ SSL option conflicts.
  defp do_deliver(subject, body) do
    with host when is_binary(host) and host != "" <- Settings.get("smtp_host"),
         user when is_binary(user) and user != "" <- Settings.get("smtp_user"),
         password when is_binary(password) and password != "" <- Settings.get("smtp_password"),
         from when is_binary(from) and from != "" <- Settings.get("email_from"),
         to_raw when is_binary(to_raw) and to_raw != "" <- Settings.get("email_to") do
      port = Settings.get_integer("smtp_port", 465)

      recipients =
        to_raw
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      # Multipart/alternative: plain-text for simple clients, HTML for everyone else.
      boundary = "verdant_#{:erlang.system_time(:millisecond)}"
      plain = body |> String.trim() |> String.replace("\n", "\r\n")
      html  = build_html_email(subject, body)

      message =
        ("From: Verdant <#{from}>\r\n" <>
           "To: #{Enum.join(recipients, ", ")}\r\n" <>
           "Subject: #{subject}\r\n" <>
           "MIME-Version: 1.0\r\n" <>
           "Content-Type: multipart/alternative; boundary=\"#{boundary}\"\r\n" <>
           "\r\n" <>
           "--#{boundary}\r\n" <>
           "Content-Type: text/plain; charset=utf-8\r\n" <>
           "\r\n" <>
           plain <>
           "\r\n\r\n" <>
           "--#{boundary}\r\n" <>
           "Content-Type: text/html; charset=utf-8\r\n" <>
           "\r\n" <>
           html <>
           "\r\n\r\n" <>
           "--#{boundary}--")
        |> dot_stuff()

      smtp_send(host, port, user, password, from, recipients, message, subject)
    else
      _ -> {:error, :not_configured}
    end
  end

  # SMTP dot-stuffing: any line beginning with "." must be escaped as ".."
  defp dot_stuff(msg), do: String.replace(msg, "\r\n.", "\r\n..")

  # ── HTML email builder ────────────────────────────────────────────────────────

  defp build_html_email(subject, body) do
    # Strip the sign-off line – it's rendered in the template footer instead.
    content =
      body
      |> String.trim()
      |> String.replace(~r/\n+— Verdant Irrigation\s*$/, "")
      |> String.trim()

    sections_html =
      content
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.map(&email_section_to_html/1)
      |> Enum.join("\n")

    # Inline-CSS table layout – the only reliable approach for email clients.
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
    </head>
    <body style="margin:0;padding:0;background-color:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f3f4f6;padding:24px 12px;">
        <tr><td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:580px;">

            <!-- Green header -->
            <tr><td style="background-color:#16a34a;padding:22px 28px;border-radius:10px 10px 0 0;">
              <table role="presentation" cellpadding="0" cellspacing="0"><tr>
                <td style="padding-right:12px;vertical-align:middle;">
                  <div style="width:38px;height:38px;background-color:rgba(255,255,255,0.18);border-radius:9px;text-align:center;line-height:38px;font-size:20px;">✨</div>
                </td>
                <td style="vertical-align:middle;">
                  <div style="color:#ffffff;font-size:19px;font-weight:700;letter-spacing:-0.3px;line-height:1.2;">Verdant</div>
                  <div style="color:rgba(255,255,255,0.72);font-size:11px;margin-top:2px;letter-spacing:0.3px;text-transform:uppercase;">Smart Irrigation</div>
                </td>
              </tr></table>
            </td></tr>

            <!-- Subject bar -->
            <tr><td style="background-color:#f0fdf4;padding:14px 28px;border-left:1px solid #bbf7d0;border-right:1px solid #bbf7d0;">
              <div style="color:#15803d;font-size:15px;font-weight:600;line-height:1.4;">#{html_escape(subject)}</div>
            </td></tr>

            <!-- Body -->
            <tr><td style="background-color:#ffffff;padding:24px 28px;border-left:1px solid #e5e7eb;border-right:1px solid #e5e7eb;">
              #{sections_html}
            </td></tr>

            <!-- Footer -->
            <tr><td style="background-color:#f9fafb;padding:14px 28px;border-radius:0 0 10px 10px;border:1px solid #e5e7eb;border-top:none;">
              <span style="color:#16a34a;font-size:12px;font-weight:600;">Verdant</span>
              <span style="color:#9ca3af;font-size:12px;"> · Smart Irrigation System</span>
            </td></tr>

          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end

  # Lines where every entry matches "Word(s): value" are rendered as a tidy
  # info-card table.  Everything else becomes a plain paragraph.
  defp email_section_to_html(section) do
    lines =
      section
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    kv_re = ~r/^[A-Za-z][A-Za-z0-9 ]+:\s+.+/

    if length(lines) > 1 and Enum.all?(lines, &Regex.match?(kv_re, &1)) do
      rows =
        Enum.map_join(lines, "\n", fn line ->
          case String.split(line, ~r/:\s+/, parts: 2) do
            [key, value] ->
              k = html_escape(key)
              v = html_escape(value)

              """
              <tr>
                <td style="padding:5px 16px 5px 0;color:#6b7280;font-size:13px;font-weight:500;white-space:nowrap;vertical-align:top;width:1%;">#{k}</td>
                <td style="padding:5px 0;color:#111827;font-size:13px;vertical-align:top;">#{v}</td>
              </tr>
              """

            _ ->
              ~s(<tr><td colspan="2" style="padding:4px 0;color:#374151;font-size:13px;">#{html_escape(line)}</td></tr>)
          end
        end)

      """
      <div style="background-color:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:14px 18px;margin-bottom:18px;">
        <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;">
          #{rows}
        </table>
      </div>
      """
    else
      text =
        lines
        |> Enum.map(&html_escape/1)
        |> Enum.join("<br>")

      ~s(<p style="margin:0 0 16px 0;color:#374151;font-size:14px;line-height:1.7;">#{text}</p>)
    end
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp smtp_send(host, port, user, password, from, recipients, message, subject) do
    ssl_opts = [
      mode: :binary,
      packet: :line,
      active: false,
      verify: :verify_peer,
      cacerts: :certifi.cacerts(),
      depth: 3,
      versions: [:"tlsv1.2", :"tlsv1.3"]
    ]

    with {:ok, sock} <- smtp_connect(host, port, ssl_opts),
         :ok <- smtp_send_line(sock, "AUTH LOGIN"),
         {:ok, _} <- smtp_recv(sock),
         :ok <- smtp_send_line(sock, Base.encode64(user)),
         {:ok, _} <- smtp_recv(sock),
         :ok <- smtp_send_line(sock, Base.encode64(password)),
         {:ok, auth_resp} <- smtp_recv(sock),
         :ok <- expect_code(auth_resp, "235"),
         :ok <- smtp_send_line(sock, "MAIL FROM:<#{from}>"),
         {:ok, _} <- smtp_recv(sock),
         :ok <- smtp_send_rcpts(sock, recipients),
         :ok <- smtp_send_line(sock, "DATA"),
         {:ok, _} <- smtp_recv(sock),
         :ok <- :ssl.send(sock, message <> "\r\n.\r\n"),
         {:ok, _} <- smtp_recv(sock) do
      smtp_send_line(sock, "QUIT")
      :ssl.close(sock)
      Logger.info("[Notifier] Sent: #{subject}")
      {:ok, :sent}
    else
      {:error, {:auth_failed, resp}} ->
        Logger.warning("[Notifier] SMTP auth failed: #{inspect(resp)}")
        {:error, :auth_failed}

      {:error, reason} = err ->
        Logger.warning("[Notifier] SMTP error for '#{subject}': #{inspect(reason)}")
        err
    end
  end

  defp smtp_recv(sock), do: :ssl.recv(sock, 0, 10_000)
  defp smtp_send_line(sock, line), do: :ssl.send(sock, line <> "\r\n")

  # Port 465 = SMTPS: server expects TLS from the very first byte (like Python's SMTP_SSL).
  # Port 587 = STARTTLS: plain TCP first, EHLO, then upgrade to TLS mid-session.
  # Returns {:ok, ssl_socket} with EHLO already completed, ready for AUTH.
  defp smtp_connect(host, port, ssl_opts) do
    host_cl = String.to_charlist(host)

    if port == 465 do
      with {:ok, sock} <- :ssl.connect(host_cl, port, ssl_opts, 15_000),
           {:ok, _} <- smtp_recv(sock),
           :ok <- smtp_send_line(sock, "EHLO verdant"),
           :ok <- drain_multi_response(sock) do
        {:ok, sock}
      end
    else
      # Plain TCP connect, read greeting, EHLO, STARTTLS, then upgrade.
      tcp_opts = [mode: :binary, packet: :line, active: false]

      with {:ok, tcp} <- :gen_tcp.connect(host_cl, port, tcp_opts, 15_000),
           {:ok, _} <- :gen_tcp.recv(tcp, 0, 10_000),
           :ok <- :gen_tcp.send(tcp, "EHLO verdant\r\n"),
           :ok <- drain_tcp_multi(tcp),
           :ok <- :gen_tcp.send(tcp, "STARTTLS\r\n"),
           {:ok, _} <- :gen_tcp.recv(tcp, 0, 10_000),
           {:ok, sock} <- :ssl.connect(tcp, ssl_opts, 15_000),
           :ok <- smtp_send_line(sock, "EHLO verdant"),
           :ok <- drain_multi_response(sock) do
        {:ok, sock}
      end
    end
  end

  # Consume a multi-line SMTP response (lines beginning "250-") until the
  # final "250 " terminator line.
  defp drain_multi_response(sock) do
    case smtp_recv(sock) do
      {:ok, <<"250-", _::binary>>} -> drain_multi_response(sock)
      {:ok, <<"250 ", _::binary>>} -> :ok
      {:ok, <<"250\r\n">>} -> :ok
      {:ok, other} -> {:error, {:unexpected_response, other}}
      error -> error
    end
  end

  # Same as drain_multi_response but for a plain TCP socket (pre-STARTTLS).
  defp drain_tcp_multi(tcp) do
    case :gen_tcp.recv(tcp, 0, 10_000) do
      {:ok, <<"250-", _::binary>>} -> drain_tcp_multi(tcp)
      {:ok, <<"250 ", _::binary>>} -> :ok
      {:ok, <<"250\r\n">>} -> :ok
      {:ok, other} -> {:error, {:unexpected_response, other}}
      error -> error
    end
  end

  defp smtp_send_rcpts(_sock, []), do: :ok

  defp smtp_send_rcpts(sock, [rcpt | rest]) do
    with :ok <- smtp_send_line(sock, "RCPT TO:<#{rcpt}>"),
         {:ok, _} <- smtp_recv(sock) do
      smtp_send_rcpts(sock, rest)
    end
  end

  defp expect_code(response, code) do
    if String.starts_with?(to_string(response), code),
      do: :ok,
      else: {:error, {:auth_failed, response}}
  end

  defp format_time(%DateTime{} = dt), do: LocalTime.format(dt)
  defp format_time(_), do: format_now()
  defp format_now, do: LocalTime.format(DateTime.utc_now())

  defp format_skip_reason(reason) do
    case reason do
      "no enabled zones" ->
        "No zones are enabled for this schedule"

      r when is_binary(r) ->
        String.capitalize(r)

      _ ->
        inspect(reason)
    end
  end
end
