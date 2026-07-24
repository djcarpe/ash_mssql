# AshMssql — MSSQL Data Layer for Ash (design)

Date: 2026-07-24
Status: Approved for planning

## Goal

Provide an Ash Framework data layer for Microsoft SQL Server, using the `tds`
driver via `Ecto.Adapters.Tds`. Ported from the existing (half-converted)
`ash_mysql` fork at `/Users/danielcarpenter/Projects/ash_mysql`, which already
sits on top of `ash_sql` (the shared SQL-building library also used by
`ash_postgres` and `ash_mysql`).

### Primary requirement

1. **`like` and `ilike` are supported** as native MSSQL `LIKE`.

## Approach

**Rename-and-adapt port.** Copy the `ash_mysql` fork into this project, globally
rename identifiers, then fix each MSSQL dialect divergence. This reuses the
proven `ash_sql` integration and is the fastest route to a compiling, functional
extension.

Rejected alternatives:
- Clean rewrite on `ash_sql`: slower, reintroduces already-solved bugs.
- Defer migration generator: contradicts the full-port goal.

## Package / naming

- App/package: `:ash_mssql`
- Root namespace: `AshMssql.*` (from `AshMysql.*`)
- Mix tasks: `ash_mssql.*` (from `ash_mysql.*`)
- Adapter: `Ecto.Adapters.Tds`
- Deps: drop `myxql`; keep `tds ~> 2.3`, `ash_sql ~> 0.2`, `ecto ~> 3.13`,
  `ecto_sql ~> 3.13`, `ash ~> 3.0`, `jason`, `picosat_elixir`. Dev/test tooling
  (`igniter`, `git_ops`, `ex_doc`, `credo`, `dialyxir`, `sobelow`, `mix_audit`,
  `ex_check`) carried over unchanged.

## Dialect adaptations (the substance of the port)

| Area | MySQL (source) | MSSQL (target) |
|---|---|---|
| `like` | `like(a, b)` | unchanged — plain `LIKE` (defers to column collation) |
| `ilike` | `like(LOWER(a), LOWER(b))` | plain `LIKE` (defers to column collation) |
| `ilike?/0` | `false` | `false` (unchanged — MSSQL has no distinct ILIKE) |
| ci_string | `VARCHAR COLLATE utf8mb4_0900_ai_ci` | `NVARCHAR` (no special collation) |
| `strpos_function` | `"instr"` — `instr(str, sub)` | `"charindex"` — `charindex(sub, str)`: **arg order reversed**, needs a custom `expr` clause to swap operands |
| `<>` concat | `CONCAT(a, b)` | `CONCAT(a, b)` (MSSQL 2012+) — keep |
| `\|\|` / `&&` truthiness | `LIKE FALSE` hack | rewrite as `CASE WHEN <x> IS NULL ...` — `LIKE FALSE` is invalid in MSSQL |
| JSON get-path | `json_extract_path` + `json_unquote` | `JSON_VALUE` (scalars) / `JSON_QUERY` (objects/arrays) |
| repo init | `case_sensitive_like: :on` | removed (MyXQL-only option, invalid for Tds) |
| errors | `%MyXQL.Error{}` | `%Tds.Error{}`; unique-violation numbers 2627 / 2601 |
| identity col | `AUTO_INCREMENT` | `IDENTITY(1,1)` |
| string col | `VARCHAR` | `NVARCHAR` |
| install task | `charset: "utf8mb4"` config | Tds connection opts (hostname, port 1433, username, password, database) |
| `verify_repo` | error text names `Ecto.Adapters.MyXQL` | names `Ecto.Adapters.Tds` |

### Collation decision

CI (case-insensitive) collation handling is **dropped**. MSSQL databases default
to a case-insensitive collation, so plain `LIKE` is already case-insensitive in
the common setup. Both `like` and `ilike` compile to native `LIKE` and defer to
the column/database collation. If a case-sensitive deployment later needs a
guaranteed `ilike`, add a `COLLATE ..._CI_AS` fragment in the single `like`/
`ilike` `expr/6` clause — a localized change.

## Components (mirrors ash_mysql structure)

- `AshMssql.DataLayer` — the Spark DSL extension + `Ash.DataLayer` behaviour
  (query building via `ash_sql`, CRUD, transactions, error translation).
- `AshMssql.DataLayer.Info` — introspection helpers (table, repo).
- `AshMssql.Repo` — thin `Ecto.Repo` wrapper (`use Ecto.Repo, adapter:
  Ecto.Adapters.Tds`), Ash <-> Ecto struct translation, `init/2` config.
- `AshMssql.SqlImplementation` — `AshSql.Implementation` callbacks: `like`/
  `ilike` expr, `strpos_function`, JSON path, type casting, concat. **Requirement
  #1 lives here.**
- `AshMssql.Functions.Like` / `AshMssql.Functions.ILike` — `Ash.Query.Function`
  definitions (`name: :like` / `:ilike`, args `[[:string, :string]]`).
- `AshMssql.MigrationGenerator` (+ `operation.ex`, `phase.ex`) — DDL generation.
- `AshMssql.Statement`, `AshMssql.Type`, `AshMssql.Reference`,
  `AshMssql.CustomIndex`, `AshMssql.CustomExtension`,
  `AshMssql.ManualRelationship`.
- Transformers: `VerifyRepo`, `ValidateReferences`, `EnsureTableOrPolymorphic`.
- Mix tasks: `ash_mssql.{create,drop,migrate,rollback,generate_migrations,install}`.

## Migration generator scope

Emit correct MSSQL DDL for the common-path types: string (`NVARCHAR`), ci_string
(`NVARCHAR`), integer identity (`IDENTITY(1,1)`), uuid (`UNIQUEIDENTIFIER` or
`BINARY(16)` per existing convention), boolean (`BIT`), datetime
(`DATETIME2`/`DATETIMEOFFSET`), decimal (`DECIMAL`), binary (`VARBINARY`), json
(`NVARCHAR(MAX)`). For exotic/unhandled types, raise or warn with a clear message
rather than silently emit wrong DDL.

## Testing / verification

- `mix compile` must be clean (warnings-as-errors where the fork already sets it).
- Unit-level: a test resource with a string attribute; assert the compiled query
  for `like`/`ilike` filters produces native `LIKE` SQL (inspect generated SQL
  via `Ecto`/`ash_sql`, no live DB required).
- Integration tests are structured (`test/support`, sandbox setup) but require a
  running SQL Server to execute; they are not expected to pass in CI without a DB.
- `strpos`/`contains` arg-order and JSON-path clauses get targeted unit coverage.

## Known risk areas (flagged, not hidden)

- `strpos`/`charindex` argument order (reversed vs MySQL).
- `||` / `&&` truthiness rewrite (MySQL `LIKE FALSE` idiom does not port).
- JSON path semantics (`JSON_VALUE` returns NULL for non-scalar; `JSON_QUERY`
  for objects/arrays).
- `OFFSET ... FETCH` in MSSQL requires an `ORDER BY`; confirm `ash_sql`/Ecto Tds
  adapter handles limit/offset without a manual order.
- Unique-constraint error parsing (2627 vs 2601, message format differs from
  MyXQL).
