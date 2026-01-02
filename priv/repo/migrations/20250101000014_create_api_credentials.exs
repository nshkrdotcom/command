defmodule Command.Repo.Migrations.CreateApiCredentials do
  use Ecto.Migration

  def change do
    create table(:api_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Identity
      # User-friendly name
      add :name, :string, null: false
      # "anthropic", "openai", "google", "github", etc.
      add :provider, :string, null: false

      # Encrypted credential storage
      # The actual key is encrypted at the application level before storage
      add :encrypted_key, :binary, null: false
      # Last 4 chars for identification
      add :key_hint, :string

      # Status
      # "active", "revoked", "expired"
      add :status, :string, default: "active"

      # Validation
      add :last_validated_at, :utc_datetime_usec
      add :validation_error, :string

      # Usage tracking
      add :last_used_at, :utc_datetime_usec
      add :use_count, :integer, default: 0

      # Scope/permissions (provider-specific)
      add :scopes, {:array, :string}, default: []

      # Expiration
      add :expires_at, :utc_datetime_usec

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:api_credentials, [:user_id])
    create index(:api_credentials, [:provider])
    create unique_index(:api_credentials, [:user_id, :provider, :name])
    create index(:api_credentials, [:status])
  end
end
