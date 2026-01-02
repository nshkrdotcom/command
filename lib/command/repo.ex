defmodule Command.Repo do
  @moduledoc """
  The Command Ecto repository.

  Provides database access for all Command schemas.
  """

  use Ecto.Repo,
    otp_app: :command,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Dynamically loads the repository url from the DATABASE_URL environment variable.
  """
  def init(_type, config) do
    {:ok, Keyword.put(config, :url, System.get_env("DATABASE_URL") || config[:url])}
  end

  @doc """
  A helper for transactional operations.
  """
  @spec run_transaction((-> result)) :: {:ok, result} | {:error, term()} when result: term()
  def run_transaction(fun) when is_function(fun, 0) do
    transaction(fn -> fun.() end)
  end
end
