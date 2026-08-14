defmodule AshMssql.EctoAdapter do
  @moduledoc """
  An `Ecto.Adapter` that wraps `Ecto.Adapters.Tds`, correcting UUID byte
  order for `:uuid`-typed values (such as `Ash.Type.UUID` and
  `Ash.Type.UUIDv7`).

  SQL Server's `uniqueidentifier` stores the first three groups of a UUID
  little-endian (its string form byte-swaps them relative to the RFC 4122
  binary encoding), while Ash's UUID types dump to the big-endian RFC
  encoding. `Ecto.Adapters.Tds` only compensates for this for the
  `:binary_id` primitive (via `Tds.Ecto.UUID`), so `:uuid`-typed values
  would be stored with their internal bytes misinterpreted: the value
  SQL Server renders (`CONVERT(nvarchar, col)`, SSMS, other clients) would
  be a byte-swapped variant of the UUID the application sees, and
  server-side lookups by UUID string would not find the row.

  This adapter converts `:uuid` values into the layouts described in
  `AshMssql.UUID` on dump and back on load: SQL Server's native byte order
  for most UUIDs (so the database-side string and binary forms agree with
  the application-side UUID), and a rotated, index-friendly layout for
  version 7 UUIDs (so time-ordered v7 keys insert sequentially instead of
  at random index positions — see `AshMssql.UUID` for the trade-off).

  Because values pass through this adapter's `dumpers/2`, use plain
  `:uuid`-typed (Ash or Ecto) types with it — not `Tds.Ecto.UUID`, which
  would swap the bytes a second time.
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Migration
  @behaviour Ecto.Adapter.Queryable
  @behaviour Ecto.Adapter.Schema
  @behaviour Ecto.Adapter.Storage
  @behaviour Ecto.Adapter.Transaction

  alias Ecto.Adapters.Tds

  @impl Ecto.Adapter
  defmacro __before_compile__(env) do
    Ecto.Adapters.SQL.__before_compile__(:tds, env)
  end

  @impl Ecto.Adapter
  defdelegate ensure_all_started(config, type), to: Tds

  @impl Ecto.Adapter
  defdelegate init(config), to: Tds

  @impl Ecto.Adapter
  defdelegate checkout(meta, opts, fun), to: Tds

  @impl Ecto.Adapter
  defdelegate checked_out?(meta), to: Tds

  @impl Ecto.Adapter
  def loaders(:uuid, type), do: [&load_uuid/1, type]
  def loaders(primitive, type), do: Tds.loaders(primitive, type)

  @impl Ecto.Adapter
  def dumpers(:uuid, type), do: [type, &dump_uuid/1]
  def dumpers(primitive, type), do: Tds.dumpers(primitive, type)

  # Stored `uniqueidentifier` bytes -> RFC 4122 big-endian, which is what
  # `:uuid` ecto types load.
  defp load_uuid(<<_::128>> = value), do: {:ok, AshMssql.UUID.from_stored(value)}
  defp load_uuid(value), do: {:ok, value}

  # Runs after the ecto type's own dump, which produces RFC 4122 big-endian
  # bytes. Non-16-byte values (nil, or strings from a raw `:uuid` primitive
  # cast) pass through for the driver to handle.
  defp dump_uuid(<<_::128>> = value), do: {:ok, AshMssql.UUID.to_stored(value)}
  defp dump_uuid(value), do: {:ok, value}

  @impl Ecto.Adapter.Queryable
  defdelegate prepare(operation, query), to: Tds

  @impl Ecto.Adapter.Queryable
  defdelegate execute(adapter_meta, query_meta, query_cache, params, options), to: Tds

  @impl Ecto.Adapter.Queryable
  defdelegate stream(adapter_meta, query_meta, query_cache, params, options), to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate autogenerate(field_type), to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate insert_all(
                adapter_meta,
                schema_meta,
                header,
                rows,
                on_conflict,
                returning,
                placeholders,
                options
              ),
              to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate insert(adapter_meta, schema_meta, fields, on_conflict, returning, options), to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate update(adapter_meta, schema_meta, fields, filters, returning, options), to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate delete(adapter_meta, schema_meta, filters, returning, options), to: Tds

  @impl Ecto.Adapter.Transaction
  defdelegate transaction(adapter_meta, options, function), to: Tds

  @impl Ecto.Adapter.Transaction
  defdelegate in_transaction?(adapter_meta), to: Tds

  @impl Ecto.Adapter.Transaction
  defdelegate rollback(adapter_meta, value), to: Tds

  @impl Ecto.Adapter.Migration
  defdelegate supports_ddl_transaction?, to: Tds

  @impl Ecto.Adapter.Migration
  defdelegate execute_ddl(adapter_meta, command, options), to: Tds

  @impl Ecto.Adapter.Migration
  defdelegate lock_for_migrations(adapter_meta, options, fun), to: Tds

  @impl Ecto.Adapter.Storage
  defdelegate storage_up(options), to: Tds

  @impl Ecto.Adapter.Storage
  defdelegate storage_down(options), to: Tds

  @impl Ecto.Adapter.Storage
  defdelegate storage_status(options), to: Tds
end
