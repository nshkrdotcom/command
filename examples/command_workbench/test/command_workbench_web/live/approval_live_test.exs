defmodule CommandWorkbenchWeb.ApprovalLiveTest do
  use CommandWorkbenchWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    email = "test-#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Command.Accounts.create_user(%{email: email})

    {:ok, item} =
      Command.Approvals.create_approval_item(user, %{
        approval_type: "tool_use",
        title: "Approve tool",
        payload: %{"tool" => "bash", "command" => "ls"},
        source_type: "manual"
      })

    conn = assign(conn, :current_user, user)
    %{conn: conn, user: user, item: item}
  end

  test "lists approvals", %{conn: conn, item: item} do
    {:ok, _view, html} = live(conn, ~p"/approvals")

    assert html =~ "Pending Approvals"
    assert html =~ item.title
  end

  test "approves an item", %{conn: conn, item: item} do
    {:ok, view, _html} = live(conn, ~p"/approvals")

    view
    |> element("button", "Approve")
    |> render_click()

    refute render(view) =~ item.title
  end
end
