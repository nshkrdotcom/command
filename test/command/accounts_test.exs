defmodule Command.AccountsTest do
  use Command.DataCase, async: true

  alias Command.Accounts
  alias Command.Accounts.{ApiCredential, User}

  describe "users" do
    test "create_user/1 with valid data creates a user" do
      attrs = %{email: "test@example.com", name: "Test User"}

      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      assert user.status == "active"
    end

    test "create_user/1 with invalid data returns error changeset" do
      attrs = %{email: "invalid"}

      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(attrs)
    end

    test "create_user/1 requires email" do
      attrs = %{name: "Test User"}

      assert {:error, changeset} = Accounts.create_user(attrs)
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_user/1 validates email format" do
      attrs = %{email: "invalid-email"}

      assert {:error, changeset} = Accounts.create_user(attrs)
      assert %{email: ["must have @ sign and no spaces"]} = errors_on(changeset)
    end

    test "get_user/1 returns the user with given id" do
      user = insert(:user)

      assert Accounts.get_user(user.id) == user
    end

    test "get_user/1 returns nil for non-existent id" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end

    test "get_user_by_email/1 returns the user with given email" do
      user = insert(:user, email: "findme@example.com")

      assert Accounts.get_user_by_email("findme@example.com") == user
    end

    test "update_user_profile/2 updates profile fields" do
      user = insert(:user)

      assert {:ok, updated} = Accounts.update_user_profile(user, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "update_user_preferences/2 updates preferences" do
      user = insert(:user)

      assert {:ok, updated} = Accounts.update_user_preferences(user, %{theme: "dark"})
      assert updated.preferences == %{theme: "dark"}
    end

    test "update_user_status/2 updates status" do
      user = insert(:user)

      assert {:ok, updated} = Accounts.update_user_status(user, "inactive")
      assert updated.status == "inactive"
    end

    test "list_users/1 returns all users" do
      user1 = insert(:user)
      user2 = insert(:user)

      users = Accounts.list_users()

      assert length(users) >= 2
      assert user1 in users
      assert user2 in users
    end

    test "list_users/1 filters by status" do
      active_user = insert(:user, status: "active")
      _inactive_user = insert(:user, status: "inactive")

      users = Accounts.list_users(status: "active")

      assert active_user in users
    end
  end

  describe "api_credentials" do
    test "create_api_credential/2 creates a credential" do
      user = insert(:user)
      attrs = %{name: "My API Key", provider: "anthropic", api_key: "sk-test-key-1234"}

      assert {:ok, %ApiCredential{} = credential} = Accounts.create_api_credential(user, attrs)
      assert credential.name == "My API Key"
      assert credential.provider == "anthropic"
      assert credential.key_hint == "1234"
      assert credential.status == "active"
    end

    test "create_api_credential/2 validates provider" do
      user = insert(:user)
      attrs = %{name: "Key", provider: "invalid", api_key: "key"}

      assert {:error, changeset} = Accounts.create_api_credential(user, attrs)
      assert %{provider: ["is invalid"]} = errors_on(changeset)
    end

    test "get_api_credential_by_provider/2 returns active credential" do
      user = insert(:user)

      {:ok, credential} =
        Accounts.create_api_credential(user, %{
          name: "Anthropic Key",
          provider: "anthropic",
          api_key: "sk-test"
        })

      assert Accounts.get_api_credential_by_provider(user, "anthropic") == credential
    end

    test "list_api_credentials/1 returns user's credentials" do
      user = insert(:user)

      {:ok, cred1} =
        Accounts.create_api_credential(user, %{
          name: "Key 1",
          provider: "anthropic",
          api_key: "sk-1"
        })

      {:ok, cred2} =
        Accounts.create_api_credential(user, %{
          name: "Key 2",
          provider: "openai",
          api_key: "sk-2"
        })

      credentials = Accounts.list_api_credentials(user)

      assert length(credentials) == 2
      assert cred1 in credentials
      assert cred2 in credentials
    end

    test "revoke_api_credential/1 sets status to revoked" do
      user = insert(:user)

      {:ok, credential} =
        Accounts.create_api_credential(user, %{
          name: "Key",
          provider: "anthropic",
          api_key: "sk-test"
        })

      assert {:ok, revoked} = Accounts.revoke_api_credential(credential)
      assert revoked.status == "revoked"
    end

    test "record_credential_usage/1 updates usage stats" do
      user = insert(:user)

      {:ok, credential} =
        Accounts.create_api_credential(user, %{
          name: "Key",
          provider: "anthropic",
          api_key: "sk-test"
        })

      assert credential.use_count == 0
      assert credential.last_used_at == nil

      assert {:ok, updated} = Accounts.record_credential_usage(credential)
      assert updated.use_count == 1
      assert updated.last_used_at != nil
    end
  end
end
