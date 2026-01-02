# Script for populating the database.
#
# You can run it with:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Command.Repo.insert!(%Command.SomeSchema{})
#

alias Command.Repo
alias Command.Accounts.User

# Create a default development user if not exists
case Repo.get_by(User, email: "dev@command.local") do
  nil ->
    Repo.insert!(%User{
      email: "dev@command.local",
      name: "Development User",
      status: "active",
      preferences: %{
        theme: "dark",
        notifications: true
      }
    })

    IO.puts("Created development user: dev@command.local")

  _user ->
    IO.puts("Development user already exists")
end
