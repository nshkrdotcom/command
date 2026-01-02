defmodule CommandWorkbenchWeb.SessionLiveTest do
  use CommandWorkbenchWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    email = "test-#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Command.Accounts.create_user(%{email: email})
    {:ok, session} = Command.Sessions.create_session(user, %{name: "Test Session"})

    conn = assign(conn, :current_user, user)
    %{conn: conn, user: user, session: session}
  end

  describe "Index" do
    test "lists sessions", %{conn: conn, session: session} do
      {:ok, _view, html} = live(conn, ~p"/sessions")

      assert html =~ "Sessions"
      assert html =~ session.name
    end

    test "creates new session", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sessions")

      view
      |> element("a", "New Session")
      |> render_click()

      assert_patch(view, ~p"/sessions/new")

      view
      |> form("#session-form", session: %{name: "New Test Session"})
      |> render_submit()

      assert_patch(view, ~p"/sessions")
      assert render(view) =~ "New Test Session"
    end
  end

  describe "Show" do
    test "displays session", %{conn: conn, session: session} do
      {:ok, _view, html} = live(conn, ~p"/sessions/#{session}")

      assert html =~ session.name
    end

    test "sends message", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/sessions/#{session}")

      view
      |> form("form", %{content: "Hello agent"})
      |> render_submit()

      assert render(view) =~ "Hello agent"
    end

    test "receives messages via PubSub", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/sessions/#{session}")

      {:ok, _message} =
        Command.Sessions.create_message(session, %{role: "assistant", content: "Hello human"})

      assert render(view) =~ "Hello human"
    end
  end
end
