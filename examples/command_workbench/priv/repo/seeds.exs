alias Command.Accounts

case Accounts.get_user_by_email("demo@example.com") do
  nil ->
    {:ok, _} = Accounts.create_user(%{email: "demo@example.com", name: "Demo User"})

  _ ->
    :ok
end
