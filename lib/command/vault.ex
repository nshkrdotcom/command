defmodule Command.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive data at rest.

  Used for encrypting API credentials and other sensitive fields
  before storing them in the database.
  """

  use Cloak.Vault, otp_app: :command
end
