# Rules for working with AshMssql

## Understanding AshMssql

AshMssql is the Microsoft SQL Server data layer for Ash Framework, built on the
`tds` driver via `AshMssql.EctoAdapter`, a thin wrapper around `Ecto.Adapters.Tds`
that stores `:uuid` values (e.g. `Ash.Type.UUID`, `Ash.Type.UUIDv7`) in SQL
Server's native `uniqueidentifier` byte order, so ids render and compare the
same in the application, the database, and any other client of the same
database. Repos must use `use AshMssql.Repo`, which selects this adapter.
Note that SQL Server sorts uniqueidentifiers by their *last* string group
first, so `uuid_v7` primary keys do not insert sequentially into a clustered
index the way they do on byte-wise-comparing databases; prefer
`integer_primary_key` when insert locality matters.
Like ash_postgres, generated migrations map well-known generator defaults to
database-side DEFAULTs, so rows inserted outside Ash get the same generated
values: `NEWID()` for `uuid_primary_key`, a T-SQL RFC 9562 v7 builder for
`uuid_v7_primary_key`, `SYSUTCDATETIME()` for `&DateTime.utc_now/0` and
`&NaiveDateTime.utc_now/0` (timestamps), and `CAST(SYSUTCDATETIME() AS date)`
for `&Date.utc_today/0`. For attributes carrying one of these Ash defaults,
Ash fills the value client-side on its own writes, so their column DEFAULTs
only fire for rows written outside Ash — whereas `generated?: true`
attributes (below) have no Ash default and are filled by the database on
every insert, Ash's included. Note these DEFAULTs fire only on INSERT — SQL
Server has no ON UPDATE mechanism, so updates made outside Ash must set
`updated_at` themselves (Ash sets it client-side on its own updates).
For a column the *database* should fill, declare a `:uuid` or `:uuid_v7`
attribute with `generated?: true` and no default: the migration generator
emits the matching column DEFAULT automatically and the value is read back
after writes (an attribute with an Ash `default` is always filled
client-side, so the column DEFAULT would never fire).
It sits on the shared `ash_sql` query-building
library, the same foundation used by `ash_postgres`, so most Ash querying,
filtering, calculation, aggregate, and relationship features work the same way.

Reach for AshMssql when you must run against SQL Server. If you are free to choose
a database, `ash_postgres` is the more fully-featured default. Modern SQL Server
(2017+/2019/2022) is the supported target.

Using AshMssql gives you the declarative structure of Ash together with SQL Server
as the backing store. Configure resources with the data layer and a repo:

```elixir
defmodule MyApp.Post do
  use Ash.Resource, domain: MyApp.Domain, data_layer: AshMssql.DataLayer

  mssql do
    table "posts"
    repo MyApp.Repo
  end
end

defmodule MyApp.Repo do
  use AshMssql.Repo, otp_app: :my_app
end
```

## Migrations and tasks

- Generate migrations from resource snapshots with `mix ash_mssql.generate_migrations`.
- Manage the database with `mix ash_mssql.create`, `mix ash_mssql.migrate`,
  `mix ash_mssql.rollback`, and `mix ash_mssql.drop`.
- Tables are emitted in dependency order (a referenced table is created before any
  table that references it) because SQL Server declares foreign keys inline in
  `CREATE TABLE`. Mutual/cyclic foreign keys cannot be expressed with inline FKs.
- Prefer a `uuid_primary_key` (stored as `uniqueidentifier`). Integer identity keys
  work (`bigint IDENTITY`), and inserts read the key back via the `OUTPUT` clause.

## SQL Server dialect specifics

These are the places SQL Server diverges from PostgreSQL/MySQL. Keep them in mind
when writing filters, identities, and expressions.

- **`like` / `ilike`**: postgres-parity semantics regardless of the column or
  database collation: `like` is case-sensitive (forced via
  `COLLATE Latin1_General_CS_AS`), `ilike` is case-insensitive (both sides
  lowercased). `like` on a `ci_string` attribute matches case-insensitively,
  mirroring postgres citext.
- **`ci_string`**: maps to a sized `NVARCHAR` column (honoring the attribute's
  `max_length` constraint, 255 by default) with an explicit
  `collation: "SQL_Latin1_General_CP1_CI_AS"` — a deterministic
  case-insensitive (accent-sensitive, like postgres citext) collation — so
  equality, uniqueness, and sorting are case-insensitive even on
  servers/databases created with a case-sensitive default collation. Note:
  changing an existing column's collation via `ALTER COLUMN` fails on SQL
  Server if an index depends on the column; drop and recreate the index
  around the `modify` in that case.
- **Plain `string` equality**: `==`, `ORDER BY`, and unique indexes on regular
  `string` columns follow the column/database collation (case-insensitive on a
  default SQL Server install; case-sensitive on Postgres). If you need
  postgres-style case-sensitive equality for a column, set a collated type
  per-attribute via `migration_types(field: :"NVARCHAR(255) COLLATE Latin1_General_CS_AS")`.
- **Unique constraints and NULLs**: unique indexes are generated as *filtered*
  indexes (`WHERE <cols> IS NOT NULL`) so multiple rows with NULL key values are
  allowed, matching the Postgres/MySQL "NULLs are distinct" behaviour. Without
  this, SQL Server treats NULLs as equal and permits only one NULL row.
- **`contains/2` / `string_starts_with/2` / `string_ends_with/2` /
  `string_position/2`**: case-sensitive (postgres parity), forced via a
  case-sensitive collation; a `ci_string` operand or `Ash.CiString` literal
  matches case-insensitively. Literal needles compile to LIKE patterns with
  `[`, `%`, `_` escaped via bracket classes; dynamic needles use
  `CHARINDEX(needle, haystack)`.
- **`&&` / `||`**: follow Elixir truthiness (`nil`/`false` are falsy; `0` and `""`
  are truthy). For booleans a `0`/false value is also falsy.
- **JSON**: scalar path access (`get_path`) uses `JSON_VALUE`. Extracting whole
  objects/arrays is not handled.
- **Arrays**: SQL Server has no array column type, so `{:array, _}` attributes are
  not supported in migrations.
- **Tables with triggers**: supported. SQL Server rejects a DML statement whose
  `OUTPUT` clause has no `INTO` clause when the target table has enabled
  triggers, so creates and upserts capture their `OUTPUT` rows in a temp table
  and select them back rather than returning them from the write itself. This
  is unconditional, so no configuration is needed when a trigger is added to an
  existing table. It does mean a returning write reads the target table's shape,
  so the connection needs `SELECT` on it as well as `INSERT`.

## Upserts

Upserts are supported (`Ash.create!(..., upsert?: true)` and bulk upserts).

- Non-atomic upserts use a single SQL Server `MERGE ... OUTPUT` statement.
- Upserts that include atomic expressions (`atomic_update/3`) reference the
  existing row, which a `MERGE` value source cannot express, so they run as an
  insert followed by an atomic `UPDATE` on conflict.
- `created_at`-style create timestamps are preserved on conflict; `updated_at`
  update-defaults are refreshed.

## Transactions

Transactions are supported (`Ash.DataLayer.can?(resource, :transact)` is `true`),
backed by `Ecto.Repo` transactions on the SQL Server connection. Multi-step
actions, reactors, and bulk operations are wrapped in a transaction as usual.

Note: atomic upserts (an upsert whose changeset carries `atomic_update/3`) run as
a SELECT-then-INSERT/UPDATE inside the surrounding transaction rather than a
single `MERGE`, because atomic expressions reference the existing row. Non-atomic
upserts still use a single `MERGE`.
