# Testing With MSSQL

Testing resources with MSSQL generally requires passing `async?: false` to
your tests, due to `MSSQL`'s limitation of having a single write transaction
open at any one time.

This should be coupled with to make sure that Ash does not spawn any tasks.

```elixir
config :ash, :disable_async?, true
```
