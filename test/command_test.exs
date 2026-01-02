defmodule CommandTest do
  use ExUnit.Case

  test "version/0 returns the version" do
    assert Command.version() == "0.1.0"
  end
end
