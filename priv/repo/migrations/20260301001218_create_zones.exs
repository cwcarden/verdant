defmodule Verdant.Repo.Migrations.CreateZones do
  use Ecto.Migration

  def change do
    create table(:zones) do
      add :name, :string, null: false
      add :description, :string, default: ""
      add :gpio_pin, :integer, null: false
      add :position, :integer, null: false
      add :enabled, :boolean, default: true, null: false
      add :water_heads, :integer, default: 0
      add :flow_rate_gpm, :float, default: 0.0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:zones, [:gpio_pin])
    create unique_index(:zones, [:position])
  end
end
