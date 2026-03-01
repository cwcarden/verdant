defmodule Verdant.Settings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "settings" do
    field :key, :string
    field :value, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :description])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
