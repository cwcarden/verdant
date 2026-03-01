defmodule Verdant.Repo.Migrations.CreateScheduleZones do
  use Ecto.Migration

  def change do
    create table(:schedule_zones) do
      add :schedule_id, references(:schedules, on_delete: :delete_all), null: false
      add :zone_id, references(:zones, on_delete: :delete_all), null: false
      add :enabled, :boolean, default: true, null: false
      add :runtime_seconds, :integer, default: 600, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:schedule_zones, [:schedule_id, :zone_id])
    create index(:schedule_zones, [:zone_id])
  end
end
