# Rules for working with AshMssql

## Understanding AshMssql

AshMssql is the Microsoft SQL Server data layer for Ash Framework, built on the
`tds` driver (`Ecto.Adapters.Tds`). It sits on the shared `ash_sql` query-building
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

- **`like` / `ilike`**: SQL Server has no distinct case-insensitive `LIKE`
  operator, so both `like` and `ilike` compile to a native `LIKE`.
  Case-sensitivity is governed by the column/database collation. A default SQL
  Server install uses a case-insensitive collation (`*_CI_AS`), so `LIKE` — and
  therefore `ilike` — is case-insensitive; on Postgres/MySQL a plain `like` would
  be case-sensitive. Do not rely on `ilike` forcing case-insensitivity on a
  case-sensitive (`*_CS_AS`) column.
- **`ci_string`**: maps to `NVARCHAR` with no explicit collation; case-insensitive
  comparison comes from the column/database collation.
- **Unique constraints and NULLs**: unique indexes are generated as *filtered*
  indexes (`WHERE <cols> IS NOT NULL`) so multiple rows with NULL key values are
  allowed, matching the Postgres/MySQL "NULLs are distinct" behaviour. Without
  this, SQL Server treats NULLs as equal and permits only one NULL row.
- **`contains/2`**: compiles to `CHARINDEX(needle, haystack) > 0`.
- **`&&` / `||`**: follow Elixir truthiness (`nil`/`false` are falsy; `0` and `""`
  are truthy). For booleans a `0`/false value is also falsy.
- **JSON**: scalar path access (`get_path`) uses `JSON_VALUE`. Extracting whole
  objects/arrays is not handled.
- **Arrays**: SQL Server has no array column type, so `{:array, _}` attributes are
  not supported in migrations.

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
