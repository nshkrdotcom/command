defmodule Command.Repo.Paginator do
  @moduledoc """
  Cursor and offset-based pagination for Command queries.
  """

  import Ecto.Query

  @default_limit 20
  @max_limit 100

  @type page_opts :: [
          limit: pos_integer(),
          after: String.t() | nil,
          before: String.t() | nil,
          order_by: atom() | {atom(), :asc | :desc}
        ]

  @type page_result(t) :: %{
          entries: [t],
          page_info: %{
            has_next_page: boolean(),
            has_previous_page: boolean(),
            start_cursor: String.t() | nil,
            end_cursor: String.t() | nil
          }
        }

  @doc """
  Paginates a query using cursor-based pagination.
  """
  @spec paginate(Ecto.Query.t(), page_opts()) :: page_result(term())
  def paginate(query, opts \\ []) do
    limit = min(Keyword.get(opts, :limit, @default_limit), @max_limit)
    after_cursor = Keyword.get(opts, :after)
    before_cursor = Keyword.get(opts, :before)
    order = Keyword.get(opts, :order_by, {:inserted_at, :desc})

    query
    |> apply_cursor(after_cursor, before_cursor, order)
    |> limit(^(limit + 1))
    |> Command.Repo.all()
    |> build_page_result(limit, after_cursor, before_cursor)
  end

  defp apply_cursor(query, nil, nil, _order), do: query

  defp apply_cursor(query, after_cursor, nil, {field, :desc}) do
    {:ok, cursor_value} = decode_cursor(after_cursor)
    where(query, [r], field(r, ^field) < ^cursor_value)
  end

  defp apply_cursor(query, after_cursor, nil, {field, :asc}) do
    {:ok, cursor_value} = decode_cursor(after_cursor)
    where(query, [r], field(r, ^field) > ^cursor_value)
  end

  defp apply_cursor(query, nil, before_cursor, {field, :desc}) do
    {:ok, cursor_value} = decode_cursor(before_cursor)
    where(query, [r], field(r, ^field) > ^cursor_value)
  end

  defp apply_cursor(query, nil, before_cursor, {field, :asc}) do
    {:ok, cursor_value} = decode_cursor(before_cursor)
    where(query, [r], field(r, ^field) < ^cursor_value)
  end

  defp build_page_result(entries, limit, after_cursor, before_cursor) do
    has_more = length(entries) > limit
    entries = Enum.take(entries, limit)

    %{
      entries: entries,
      page_info: %{
        has_next_page: has_more,
        has_previous_page: after_cursor != nil or before_cursor != nil,
        start_cursor: encode_cursor(List.first(entries)),
        end_cursor: encode_cursor(List.last(entries))
      }
    }
  end

  defp encode_cursor(nil), do: nil
  defp encode_cursor(%{id: id}), do: Base.url_encode64(id, padding: false)

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) do
    case Base.url_decode64(cursor, padding: false) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_cursor}
    end
  end
end
