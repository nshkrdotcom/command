defmodule Command.EncryptedBinary do
  @moduledoc """
  Encrypted binary field type for Ecto schemas.

  Uses the Command.Vault for encryption/decryption.
  """

  use Cloak.Ecto.Binary, vault: Command.Vault
end
