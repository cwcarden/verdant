# Verdant

Smart irrigation management system built with Elixir + Phoenix LiveView, designed for Raspberry Pi.

## Features

- **Dashboard** — live zone status, active watering, weather snapshot, recent activity
- **Manual Control** — start/stop individual zones with configurable duration
- **Schedules** — configure Schedule A & B with per-zone runtimes and day selection
- **Zones** — manage zone names, GPIO pins, water heads, and flow rates
- **Weather** — Ambient Weather WS-2000 integration with historical data logging
- **Smart Skip** — auto-skip watering based on rain, wind, and temperature thresholds
- **History** — full watering session log with duration tracking
- **Dark/Light theme** — toggle via the sidebar

## Hardware

- Raspberry Pi Zero 2 W (or any Pi)
- 7-zone relay module + master valve relay
- GPIO pins (BCM): master valve = 2, zones 1-7 = pins 3-9
- Ambient Weather WS-2000 weather station

## Stack

- Elixir 1.18 / OTP 28
- Phoenix 1.8 + LiveView 1.1
- SQLite via Ecto + exqlite (lightweight, no server needed)
- DaisyUI + Tailwind CSS
- Heroicons

## Quick Start

```bash
mix deps.get
mix ecto.setup      # creates DB, runs migrations, seeds default zones & schedules
mix phx.server
```

Visit http://localhost:4000

## Raspberry Pi Deployment

```bash
# On the Pi
mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix ecto.setup
MIX_ENV=prod mix phx.server
```

Access via your VPN at the Pi's local IP on port 4000.

## First Run Checklist

1. Go to **Settings** and enter your Ambient Weather API credentials
2. Click **Fetch Now** on the Weather page to pull your first reading
3. Go to **Zones** and update names, water head counts, and flow rates
4. Configure **Schedule A** and **Schedule B** with your preferred days and runtimes
5. Enable a schedule when ready
