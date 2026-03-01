defmodule Verdant.Repo.Migrations.CreateWateringSessions do
  use Ecto.Migration

  def change do
    create table(:watering_sessions) do
      add :zone_id, references(:zones, on_delete: :nilify_all)
      add :schedule_id, references(:schedules, on_delete: :nilify_all)
      add :zone_name, :string, null: false
      add :trigger, :string, default: "manual"
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :planned_duration_seconds, :integer
      add :actual_duration_seconds, :integer
      add :skipped, :boolean, default: false, null: false
      add :skip_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:watering_sessions, [:zone_id])
    create index(:watering_sessions, [:started_at])
  end
end
