defmodule Verdant.Zones do
  import Ecto.Query
  alias Verdant.Repo
  alias Verdant.Zones.Zone

  def list_zones do
    Zone |> order_by(:position) |> Repo.all()
  end

  def get_zone!(id), do: Repo.get!(Zone, id)

  def create_zone(attrs) do
    %Zone{}
    |> Zone.changeset(attrs)
    |> Repo.insert()
  end

  def update_zone(%Zone{} = zone, attrs) do
    zone
    |> Zone.changeset(attrs)
    |> Repo.update()
  end

  def delete_zone(%Zone{} = zone), do: Repo.delete(zone)

  def change_zone(%Zone{} = zone, attrs \\ %{}), do: Zone.changeset(zone, attrs)
end
