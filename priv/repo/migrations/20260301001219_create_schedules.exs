defmodule Verdant.Repo.Migrations.CreateSchedules do
  use Ecto.Migration

  def change do
    create table(:schedules) do
      add :name, :string, null: false
      add :label, :string, default: ""
      add :enabled, :boolean, default: false, null: false
      # Comma-separated days: "0,1,2,3,4,5,6" (0=Sun, 6=Sat)
      add :days_of_week, :string, default: ""
      # Time stored as "HH:MM" string
      add :start_time, :string, default: "06:00"
      add :master_valve_warmup_seconds, :integer, default: 2

      timestamps(type: :utc_datetime)
    end

    create unique_index(:schedules, [:name])
  end
end
