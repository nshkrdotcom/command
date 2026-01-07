import Config

# Runtime configuration for production
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :command, Command.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    ssl: System.get_env("DATABASE_SSL") == "true",
    ssl_opts: [verify: :verify_none]

  config :synapse, Synapse.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    ssl: System.get_env("DATABASE_SSL") == "true",
    ssl_opts: [verify: :verify_none]

  # Vault encryption key from environment
  vault_key =
    System.get_env("VAULT_KEY") ||
      raise """
      environment variable VAULT_KEY is missing.
      Generate with: :crypto.strong_rand_bytes(32) |> Base.encode64()
      """

  config :command, Command.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: Base.decode64!(vault_key), iv_length: 12
      }
    ]
end
