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

  ## Byte order at a glance

  For a UUID with bytes `b0..b15`, as written in its string form
  (`b0 b1 b2 b3 - b4 b5 - b6 b7 - b8 b9 - b10 b11 b12 b13 b14 b15`):

      RFC 4122 raw — what Ash/Ecto uuid types dump and load:

          b0  b1  b2  b3   b4  b5   b6  b7   b8  b9   b10 b11 b12 b13 b14 b15

      stored uniqueidentifier, native layout (every version but 7) — the
      first three groups little-endian, exactly how SQL Server lays out a
      GUID whose string form equals the application uuid:

          b3  b2  b1  b0   b5  b4   b7  b6   b8  b9   b10 b11 b12 b13 b14 b15

      stored uniqueidentifier, rotated layout (version 7) — the timestamp
      (`b0..b5`) moved into the bytes SQL Server compares first:

          b15 b14 b13 b12  b11 b10  b9  b8   b6  b7   b0  b1  b2  b3  b4  b5

  SQL Server renders stored bytes `s0..s15` as the string
  `s3 s2 s1 s0 - s5 s4 - s7 s6 - s8 s9 - s10 s11 s12 s13 s14 s15`, and
  compares two uniqueidentifiers group-wise in the *opposite* order of the
  string: the last group is the most significant, the first the least.
  That comparison order is why the rotated layout exists. Concretely, the
  v7 application uuid

      00112233-4455-7677-8899-aabbccddeeff

  is stored as `ff ee dd cc bb aa 99 88 76 77 00 11 22 33 44 55` and
  rendered by the server as

      ccddeeff-aabb-8899-7677-001122334455

  while a native-layout uuid renders as exactly the application-side
  string. Storing the RFC bytes verbatim instead — what plain
  `Ecto.Adapters.Tds` does for the `:uuid` primitive — would make the
  server render the byte-swapped `33221100-5544-7776-8899-aabbccddeeff`,
  a value the application would never find by string.

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
