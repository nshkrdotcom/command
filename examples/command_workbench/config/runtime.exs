import Config

if config_env() == :prod do
  if System.get_env("PHX_SERVER") do
    config :command_workbench, CommandWorkbenchWeb.Endpoint, server: true
  end

  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :command_workbench, CommandWorkbenchWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  database_url = System.fetch_env!("DATABASE_URL")

  config :command, Command.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  vault_key = System.fetch_env!("COMMAND_VAULT_KEY")

  config :command, Command.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: Base.decode64!(vault_key), iv_length: 12
      }
    ]
end
