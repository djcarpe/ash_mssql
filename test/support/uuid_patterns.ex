defmodule AshMssql.Test.UuidPatterns do
  @moduledoc false

  # Canonical (lowercase, RFC 4122 variant) uuid shapes, shared by every test
  # that asserts on generated ids so the version/variant expectations live in
  # one place.

  def v4, do: ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

  def v7, do: ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
end
