defmodule Samgita.Domain.PlatformAuthority do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :integer, autogenerate: false}
  schema "platform_authority" do
    field :owner, :string, default: "none"
    field :admission_open, :boolean, default: false
    field :epoch, :integer, default: 1
    field :version, :integer, default: 1
    field :evidence, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
