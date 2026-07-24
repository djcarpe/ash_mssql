![Logo](https://github.com/ash-project/ash/blob/main/logos/cropped-for-header-black-text.png?raw=true#gh-light-mode-only)
![Logo](https://github.com/ash-project/ash/blob/main/logos/cropped-for-header-white-text.png?raw=true#gh-dark-mojde-only)

[![CI](https://github.com/ash-project/ash_mssql/actions/workflows/elixir.yml/badge.svg)](https://github.com/ash-project/ash_mssql/actions/workflows/elixir.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_mssql.svg)](https://hex.pm/packages/ash_mssql)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/ash_mssql)

# AshMssql

Welcome! `AshMssql` is a Microsoft SQL Server data layer for [Ash Framework](https://hexdocs.pm/ash),
built on the `tds` driver (`Ecto.Adapters.Tds`) and derived from
[`AshMysql`](https://hex.pm/packages/ash_mysql). Both sit on the shared
[`ash_sql`](https://hex.pm/packages/ash_sql) query-building library.

## Idiosyncrasies and Warnings

- AshMssql is at a very alpha stage of development: expect bugs and problems!
- It is developed against modern SQL Server (2017+/2019/2022). String
  comparison and `like`/`ilike` behaviour depend on the server/column
  collation.
- For now, you should probably use a `uuid_primary_key` in your resources
  (stored as `uniqueidentifier`). Integer identity primary keys are not yet
  fully wired.
- AshMssql maps Ash string types (including `:ci_string`) to the Ecto `:string`
  type (=> MSSQL `NVARCHAR(255)`) when generating migrations.
- **Case sensitivity of `like`/`ilike`:** MSSQL has no distinct case-insensitive
  `LIKE`, so both `like` and `ilike` compile to a native `LIKE`. Case
  sensitivity is governed by the column/database collation — on a default
  install (a `*_CI_AS` collation) `LIKE` is case-insensitive. If you need a
  guaranteed case-insensitive match on a case-sensitive column, add an explicit
  `COLLATE` in the `AshMssql.SqlImplementation` `like`/`ilike` clause.

## Tutorials

- [Get Started](documentation/tutorials/getting-started-with-ash-mssql.md)

## Topics

- [What is AshMssql?](documentation/topics/about-ash-mssql/what-is-ash-mssql.md)

### Resources

- [References](documentation/topics/resources/references.md)
- [Polymorphic Resources](documentation/topics/resources/polymorphic-resources.md)

### Development

- [Migrations and tasks](documentation/topics/development/migrations-and-tasks.md)
- [Testing](documentation/topics/development/testing.md)

### Advanced

- [Expressions](documentation/topics/advanced/expressions.md)
- [Manual Relationships](documentation/topics/advanced/manual-relationships.md)

## Reference

- [AshMssql.DataLayer DSL](documentation/dsls/DSL-AshMssql.DataLayer.md)
