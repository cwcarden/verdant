defmodule VerdantWeb.Layouts do
  @moduledoc """
  Application layouts for Verdant.
  """
  use VerdantWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :active_tab, :atom, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open min-h-screen">
      <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

      <%!-- Main content --%>
      <div class="drawer-content flex flex-col">
        <%!-- Mobile topbar --%>
        <div class="navbar bg-base-100 shadow-sm lg:hidden px-4 sticky top-0 z-10">
          <div class="flex-none">
            <label for="sidebar-drawer" class="btn btn-ghost btn-square">
              <.icon name="hero-bars-3" class="size-5" />
            </label>
          </div>
          <div class="flex-1">
            <span class="text-xl font-bold text-primary flex items-center gap-2">
              <.icon name="hero-sparkles" class="size-5" /> Verdant
            </span>
          </div>
          <div class="flex-none">
            <.theme_toggle />
          </div>
        </div>

        <%!-- Page content --%>
        <main class="flex-1 p-4 lg:p-6">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </main>
      </div>

      <%!-- Sidebar --%>
      <div class="drawer-side z-20">
        <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <aside class="bg-neutral text-neutral-content w-64 min-h-full flex flex-col">
          <%!-- Brand --%>
          <div class="px-6 py-5 border-b border-neutral-content/10">
            <div class="flex items-center gap-3">
              <div class="bg-primary rounded-xl p-2">
                <.icon name="hero-sparkles" class="size-5 text-primary-content" />
              </div>
              <div>
                <p class="text-lg font-bold tracking-tight">Verdant</p>
                <p class="text-xs text-neutral-content/50">Smart Irrigation</p>
              </div>
            </div>
          </div>

          <%!-- Navigation --%>
          <nav class="flex-1 px-3 py-4 space-y-1 sidebar-nav">
            <p class="text-xs font-semibold uppercase tracking-wider text-neutral-content/40 px-3 mb-2">
              Control
            </p>
            <.nav_item
              icon="hero-home"
              label="Dashboard"
              href={~p"/"}
              active={@active_tab == :dashboard}
            />
            <.nav_item
              icon="hero-play-circle"
              label="Manual Control"
              href={~p"/manual"}
              active={@active_tab == :manual}
            />
            <.nav_item
              icon="hero-clock"
              label="Schedules"
              href={~p"/schedules"}
              active={@active_tab == :schedules}
            />

            <div class="divider my-2 opacity-20"></div>
            <p class="text-xs font-semibold uppercase tracking-wider text-neutral-content/40 px-3 mb-2">
              Configure
            </p>
            <.nav_item
              icon="hero-adjustments-horizontal"
              label="Zones"
              href={~p"/zones"}
              active={@active_tab == :zones}
            />
            <.nav_item
              icon="hero-cloud"
              label="Weather"
              href={~p"/weather"}
              active={@active_tab == :weather}
            />

            <div class="divider my-2 opacity-20"></div>
            <p class="text-xs font-semibold uppercase tracking-wider text-neutral-content/40 px-3 mb-2">
              History
            </p>
            <.nav_item
              icon="hero-chart-bar"
              label="History"
              href={~p"/history"}
              active={@active_tab == :history}
            />

            <div class="divider my-2 opacity-20"></div>
            <.nav_item
              icon="hero-cog-6-tooth"
              label="Settings"
              href={~p"/settings"}
              active={@active_tab == :settings}
            />
          </nav>

          <%!-- Footer --%>
          <div class="px-4 py-4 border-t border-neutral-content/10">
            <div class="flex items-center justify-between">
              <span class="text-xs text-neutral-content/40">Theme</span>
              <.theme_toggle />
            </div>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :active, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors",
        if(@active,
          do: "bg-primary text-primary-content",
          else: "text-neutral-content/70 hover:bg-neutral-content/10 hover:text-neutral-content"
        )
      ]}
    >
      <.icon name={@icon} class="size-5 shrink-0" />
      {@label}
    </a>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="mb-4">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Theme toggle between verdant (light) and verdant-dark themes.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <button
        class="btn btn-ghost btn-xs btn-square"
        title="Light theme"
        phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "verdant"})}
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>
      <button
        class="btn btn-ghost btn-xs btn-square"
        title="Dark theme"
        phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "verdant-dark"})}
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
