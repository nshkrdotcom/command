defmodule Command.SessionsTest do
  use Command.DataCase, async: true

  alias Command.Sessions
  alias Command.Sessions.{Message, Session}

  describe "sessions" do
    test "create_session/2 with valid data creates a session" do
      user = insert(:user)
      attrs = %{name: "Code Review", purpose: "Review PR #123"}

      assert {:ok, %Session{} = session} = Sessions.create_session(user, attrs)
      assert session.name == "Code Review"
      assert session.purpose == "Review PR #123"
      assert session.status == "active"
      assert session.user_id == user.id
    end

    test "create_session/2 generates slug from name" do
      user = insert(:user)
      attrs = %{name: "My Test Session"}

      assert {:ok, session} = Sessions.create_session(user, attrs)
      assert session.slug == "my-test-session"
    end

    test "create_session/2 requires name" do
      user = insert(:user)

      assert {:error, changeset} = Sessions.create_session(user, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "get_session/1 returns the session" do
      session = insert(:session)

      assert Sessions.get_session(session.id).id == session.id
    end

    test "get_session_by_slug/2 returns the session" do
      user = insert(:user)
      session = insert(:session, user: user, slug: "my-session")

      assert Sessions.get_session_by_slug(user, "my-session").id == session.id
    end

    test "list_sessions/2 returns user's sessions" do
      user = insert(:user)
      session1 = insert(:session, user: user)
      session2 = insert(:session, user: user)
      _other_session = insert(:session)

      sessions = Sessions.list_sessions(user)

      assert length(sessions) == 2
      assert Enum.any?(sessions, &(&1.id == session1.id))
      assert Enum.any?(sessions, &(&1.id == session2.id))
    end

    test "list_active_sessions/1 returns only active sessions" do
      user = insert(:user)
      active = insert(:session, user: user, status: "active")
      _archived = insert(:session, user: user, status: "archived")

      sessions = Sessions.list_active_sessions(user)

      assert length(sessions) == 1
      assert hd(sessions).id == active.id
    end

    test "update_session_status/2 updates status" do
      session = insert(:session, status: "active")

      assert {:ok, updated} = Sessions.update_session_status(session, "completed")
      assert updated.status == "completed"
    end

    test "archive_session/1 archives a session" do
      session = insert(:session, status: "active")

      assert {:ok, archived} = Sessions.archive_session(session)
      assert archived.status == "archived"
    end

    test "fork_session/3 creates a forked session" do
      user = insert(:user)
      original = insert(:session, user: user)
      message = insert(:message, session: original, sequence: 5)

      assert {:ok, forked} = Sessions.fork_session(original, message, %{name: "Forked Session"})
      assert forked.parent_session_id == original.id
      assert forked.forked_at_message_id == message.id
      assert forked.name == "Forked Session"
    end

    test "increment_session_stats/2 updates stats" do
      session = insert(:session)

      assert {:ok, updated} =
               Sessions.increment_session_stats(session, %{
                 message_count: 2,
                 tokens_in: 100,
                 tokens_out: 50,
                 cost_cents: 5,
                 duration_ms: 1000
               })

      assert updated.message_count == 2
      assert updated.total_tokens_in == 100
      assert updated.total_tokens_out == 50
      assert updated.total_cost_cents == 5
      assert updated.total_duration_ms == 1000
    end
  end

  describe "messages" do
    test "create_message/2 creates a message" do
      session = insert(:session)
      attrs = %{role: "user", content: "Hello, agent!"}

      assert {:ok, %Message{} = message} = Sessions.create_message(session, attrs)
      assert message.role == "user"
      assert message.content == "Hello, agent!"
      assert message.session_id == session.id
      assert message.sequence == 1
    end

    test "create_message/2 auto-increments sequence" do
      session = insert(:session)

      {:ok, msg1} = Sessions.create_message(session, %{role: "user", content: "First"})
      {:ok, msg2} = Sessions.create_message(session, %{role: "assistant", content: "Second"})

      assert msg1.sequence == 1
      assert msg2.sequence == 2
    end

    test "create_message/2 validates role" do
      session = insert(:session)

      assert {:error, changeset} =
               Sessions.create_message(session, %{
                 role: "invalid",
                 content: "test"
               })

      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    test "list_messages/2 returns session messages in order" do
      session = insert(:session)
      {:ok, msg1} = Sessions.create_message(session, %{role: "user", content: "First"})
      {:ok, msg2} = Sessions.create_message(session, %{role: "assistant", content: "Second"})

      messages = Sessions.list_messages(session)

      assert length(messages) == 2
      assert Enum.at(messages, 0).id == msg1.id
      assert Enum.at(messages, 1).id == msg2.id
    end

    test "get_conversation_history/2 returns messages in order" do
      session = insert(:session)
      Sessions.create_message(session, %{role: "system", content: "System prompt"})
      Sessions.create_message(session, %{role: "user", content: "User message"})
      Sessions.create_message(session, %{role: "assistant", content: "Response"})

      history = Sessions.get_conversation_history(session)

      assert length(history) == 3
      assert Enum.at(history, 0).role == "system"
      assert Enum.at(history, 2).role == "assistant"
    end

    test "get_conversation_history/2 respects limit" do
      session = insert(:session)

      for i <- 1..10 do
        Sessions.create_message(session, %{role: "user", content: "Message #{i}"})
      end

      history = Sessions.get_conversation_history(session, limit: 5)

      assert length(history) == 5
    end

    test "count_messages/1 returns message count" do
      session = insert(:session)
      Sessions.create_message(session, %{role: "user", content: "1"})
      Sessions.create_message(session, %{role: "assistant", content: "2"})
      Sessions.create_message(session, %{role: "user", content: "3"})

      assert Sessions.count_messages(session) == 3
    end
  end
end
