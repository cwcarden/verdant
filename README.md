# Verdant 🌿

Smart irrigation management system built with Elixir + Phoenix LiveView, designed to run headless on a Raspberry Pi. Control your garden watering zones from any device on your local network — phone, tablet, or laptop.

---

## Features

| Page | What it does |
|------|-------------|
| **Dashboard** | Live zone status, active watering progress bars, weather snapshot, recent activity, upcoming schedule runs |
| **Manual Control** | Start/stop individual zones with custom duration (5–60 min); supports multiple concurrent zones |
| **Schedules** | Create named schedules with per-zone runtimes, day-of-week selection, and start time |
| **Zones** | Manage zone names, GPIO pins, water head counts, flow rates (GPM), and run order |
| **Weather** | Ambient Weather WS-2000 integration — current conditions + historical readings |
| **Smart Skip** | Automatically skips scheduled watering when it's rained, too windy, or temperature is out of range |
| **History** | Full audit log of every watering session — trigger, duration, status |
| **Settings** | SMTP email notifications, weather API credentials, skip thresholds, data retention |
| **PIN Lock** | Numeric passcode lock screen — keeps kids from accessing the controller |
| **Dark / Light theme** | Toggle via the sidebar |

### Email Notifications

Verdant sends styled HTML emails for:
- Schedule started / completed / skipped (with skip reason)
- Manual zone started / stopped

Uses direct SSL/STARTTLS SMTP — works with Gmail, iCloud, Fastmail, etc. Configure in Settings.

### PIN Lock Screen

Protect the controller from curious hands with an iOS-style numeric PIN lock screen.

- **4–6 digit numeric passcode** — set and change in Settings → Security
- **Enable / disable** the lock independently from removing the passcode
- **Auto-lock** — configurable idle timeout (minutes); the screen re-locks after inactivity
- **Lock Now** button in Settings for immediate manual lock
- **Forgot passcode?** — one-click email recovery sends the passcode to your configured email address
- Lock is enforced server-side (Plug session) — not bypassable from the browser
- When PIN lock is disabled or no passcode is set, the app works as normal with no lock screen

---

## Architecture

```
lib/verdant/
├── application.ex          # Supervision tree
├── zones/                  # Zone config (GPIO pin, name, flow rate)
├── schedules/              # Schedule + ScheduleZone config
├── watering/               # Session history & active-session tracking
├── irrigation/
│   ├── runner.ex           # GenServer — real-time GPIO control
│   └── scheduler.ex        # GenServer — time-based schedule triggering
├── weather/
│   ├── weather.ex          # Ambient Weather API + skip-condition logic
│   └── poller.ex           # GenServer — periodic weather fetch
├── settings.ex             # Key-value config store (SQLite-backed)
├── local_time.ex           # Timezone-aware time helpers
├── notifier.ex             # GenServer — SMTP email delivery
└── gpio/
    ├── gpio.ex             # Dispatcher (routes to adapter)
    ├── adapter.ex          # Behaviour
    ├── stub_adapter.ex     # Dev/test (logs to console)
    └── (lib_gpio/)
        └── hardware_adapter.ex  # Prod only — Circuits.GPIO

lib/verdant_web/live/
├── dashboard_live.ex
├── manual_live.ex
├── schedules_live.ex
├── zones_live.ex
├── weather_live.ex
├── history_live.ex
└── settings_live.ex
```

**Data store**: SQLite (no separate DB server required — file lives at `verdant.db`).
**Real-time UI**: Phoenix PubSub + LiveView — the dashboard updates the instant a zone starts or stops.
**GPIO**: Active-LOW relay logic — `write(pin, 0)` energizes the relay (opens the valve).

---

## Hardware

### Raspberry Pi

- **Recommended**: Raspberry Pi Zero 2 W
- Any Pi model will work (Pi 3, Pi 4, Pi 5 also supported)

### Relay Module

The app ships pre-configured for an **8-channel relay module** (zones 1–7 + master valve).
A 16-channel module works too — just add more zones in the Zones page and pick unused GPIO pins.

| Role | GPIO Pin (BCM) | Physical Pin |
|------|---------------|--------------|
| Master valve | GPIO 2 | Pin 3 |
| Zone 1 | GPIO 3 | Pin 5 |
| Zone 2 | GPIO 4 | Pin 7 |
| Zone 3 | GPIO 17 | Pin 11 |
| Zone 4 | GPIO 27 | Pin 13 |
| Zone 5 | GPIO 22 | Pin 15 |
| Zone 6 | GPIO 10 | Pin 19 |
| Zone 7 | GPIO 9 | Pin 21 |

> **Note**: These are defaults used in the seed data. You can assign any available BCM GPIO pin (2–27) to any zone from the Zones page. Pins must be unique.

#### Wiring (8-channel relay)

```
Pi GPIO pin  ──►  Relay IN1–IN8
Pi GND       ──►  Relay GND
Pi 5V        ──►  Relay VCC  (use JD-VCC jumper for opto-isolated boards)

Relay COM    ──►  24VAC common (from transformer)
Relay NO     ──►  Valve solenoid wire
Valve return ──►  24VAC return
```

**Active-LOW**: Each relay channel activates when its IN pin is pulled LOW by the Pi.
The app writes `0` to open a valve and `1` to close it.

#### Upgrading to 16 channels

1. Connect the second 8-channel board to additional GPIO pins
2. Add zones in **Settings → Zones**, assigning the new GPIO pins
3. No code changes needed — the app discovers zones from the database

### Weather Station

- [Ambient Weather WS-2000](https://ambientweather.com/ws-2000) (or any station supported by the Ambient Weather API)
- Get a free API key and Application key at [ambientweather.net/account](https://ambientweather.net/account)

---

## Will a Pi Zero 2 W Handle iPad / Network Access?

**Yes, comfortably.** The Pi Zero 2 W (quad-core 1 GHz ARM Cortex-A53, 512 MB RAM) is more than sufficient for this use case:

- Phoenix LiveView serves pre-rendered HTML + tiny WebSocket diffs — extremely low CPU/RAM per connection
- SQLite queries on irrigation data are sub-millisecond
- A home irrigation app with 1–5 concurrent users will barely register on the Pi's load average
- The Pi Zero 2 W has built-in 802.11n Wi-Fi — no Ethernet dongle needed

**Realistic performance**: page loads in ~100–200ms over local Wi-Fi; live updates instant. You won't notice it's running on a $15 computer.

---

## Prerequisites (Raspberry Pi Deployment)

### Operating System

| OS | Version | Notes |
|----|---------|-------|
| **Raspberry Pi OS Lite (64-bit)** | Bookworm (Debian 12) | ✅ Recommended — smaller footprint, no desktop |
| Raspberry Pi OS (64-bit) | Bookworm | Works, but desktop wastes RAM |
| Ubuntu Server 22.04 LTS (64-bit) | Jammy | Works |

> **Important**: Use the **64-bit** image. Erlang/OTP 26+ requires 64-bit on Pi Zero 2 W.
> Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Enable SSH and Wi-Fi in the imager settings before flashing.

### Software Versions

| Software | Minimum | Recommended |
|----------|---------|-------------|
| Erlang/OTP | 26.0 | **27.x** |
| Elixir | 1.15 | **1.18.x** |
| Node.js | 18.x | **20.x LTS** (asset build only) |

> Node.js is only needed to build assets (`mix assets.deploy`). It does not need to run on the Pi in production — just during the build step. You can build on your Mac and copy the release.

---

## Raspberry Pi Deployment Guide

### Option A — Build on Mac, Deploy to Pi (Recommended)

This avoids installing Elixir/Node on the Pi at all. Build a self-contained release on your Mac (same OS architecture caveat: Pi is ARM64, Mac M-series is also ARM64 ✅).

#### 1. Build the release on your Mac

```bash
cd verdant

# Install deps
mix deps.get --only prod

# Compile assets (minified)
MIX_ENV=prod mix assets.deploy

# Build release
MIX_ENV=prod mix release
```

The release is output to `_build/prod/rel/verdant/`.

#### 2. Set up the Pi

Flash Raspberry Pi OS Lite (64-bit, Bookworm) and SSH in.

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install runtime dependencies (no Elixir needed — the release bundles Erlang)
sudo apt install -y libncurses5 libssl-dev

# Create app directory
sudo mkdir -p /opt/verdant
sudo chown pi:pi /opt/verdant
```

#### 3. Copy the release to the Pi

```bash
# From your Mac:
rsync -av _build/prod/rel/verdant/ pi@raspberrypi.local:/opt/verdant/
```

#### 4. Configure environment

Create `/opt/verdant/.env` (or set these in the systemd unit):

```bash
export PHX_HOST=raspberrypi.local   # or your Pi's IP / hostname
export PORT=4000
export SECRET_KEY_BASE=$(./bin/verdant eval "IO.puts(:crypto.strong_rand_bytes(64) |> Base.encode64())")
export DATABASE_PATH=/opt/verdant/verdant.db
```

#### 5. Run database migrations

```bash
cd /opt/verdant
./bin/verdant eval "Verdant.Release.migrate()"
```

#### 6. Create a systemd service

```bash
sudo nano /etc/systemd/system/verdant.service
```

Paste:

```ini
[Unit]
Description=Verdant Irrigation
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=pi
WorkingDirectory=/opt/verdant
EnvironmentFile=/opt/verdant/.env
ExecStart=/opt/verdant/bin/verdant start
ExecStop=/opt/verdant/bin/verdant stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable verdant
sudo systemctl start verdant
sudo systemctl status verdant
```

#### 7. Access from iPad / any device

Open a browser and navigate to:

```
http://raspberrypi.local:4000
```

Or use the Pi's IP address if mDNS isn't working:

```bash
# Find the Pi's IP:
hostname -I
```

---

### Option B — Build directly on the Pi

If you prefer, install Elixir and Node.js on the Pi itself.

#### Install Elixir (via asdf — recommended)

```bash
# Install asdf prerequisites
sudo apt install -y curl git build-essential libssl-dev libncurses5-dev

# Install asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.1
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
source ~/.bashrc

# Install Erlang plugin + build deps
sudo apt install -y libwxgtk3.2-dev libgl1-mesa-dev libglu1-mesa-dev \
  libpng-dev libssh-dev unixodbc-dev xsltproc fop libxml2-utils
asdf plugin add erlang
asdf install erlang 27.2
asdf global erlang 27.2

# Install Elixir
asdf plugin add elixir
asdf install elixir 1.18.3-otp-27
asdf global elixir 1.18.3-otp-27

# Install Node.js (for asset build)
asdf plugin add nodejs
asdf install nodejs 20.18.0
asdf global nodejs 20.18.0
```

#### Build and run

```bash
cd /opt/verdant   # or wherever you cloned the repo
mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix ecto.setup
MIX_ENV=prod mix phx.server
```

Then set up the systemd service as in Option A step 6, replacing `ExecStart` with:

```ini
ExecStart=/home/pi/.asdf/shims/mix phx.server
Environment=MIX_ENV=prod
```

---

## Local Development

```bash
mix deps.get
mix ecto.setup      # creates SQLite DB, runs migrations, seeds default zones & schedules
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000)

The stub GPIO adapter is used in dev — all relay operations are logged to the console instead of touching hardware.

---

## First Run Checklist

1. Open **Settings**
   - Set your **timezone**
   - Enter your **Ambient Weather API key**, App key, and station MAC address
   - Configure **SMTP email** settings (optional) and send a test email
2. Go to **Weather** → click **Fetch Now** to pull your first reading
3. Go to **Zones** — update names, water head counts, and flow rates for each zone
4. Go to **Schedules** — configure your watering schedule with preferred days, start time, and per-zone runtime
5. Enable a schedule when ready

---

## Database

SQLite database file location:

| Environment | Path |
|-------------|------|
| Development | `verdant_dev.db` (project root) |
| Test | in-memory |
| Production | `$DATABASE_PATH` env var, or `verdant.db` in the release directory |

Backups: simply copy the `.db` file. Verdant uses a single-file SQLite database — no dump needed.

---

## License

MIT — see [LICENSE](LICENSE).
