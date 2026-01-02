defmodule Command.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :name, :string
      add :avatar_url, :string

      # Auth - flexible for multiple strategies later
      # "local", "github", "google", etc.
      add :auth_provider, :string
      # External provider UID
      add :auth_uid, :string
      # For local auth
      add :password_hash, :string

      # Preferences stored as JSONB for flexibility
      add :preferences, :map, default: %{}

      # API keys for this user (encrypted at app level)
      add :api_keys, :map, default: %{}, null: false

      # Status
      add :status, :string, default: "active", null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    create unique_index(:users, [:auth_provider, :auth_uid],
             where: "auth_provider IS NOT NULL AND auth_uid IS NOT NULL"
           )

    create index(:users, [:status])
  end
end
