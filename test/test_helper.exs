ExUnit.start()
ExUnit.configure(stacktrace_depth: 100)

# The migration-generator tests intentionally (re)define resource modules with
# the same names across test cases. Allow that without noisy "redefining module"
# warnings (these tests are `async: false`, so redefinition is safe).
Code.compiler_options(ignore_module_conflict: true)

AshMssql.TestRepo.start_link()

Ecto.Adapters.SQL.Sandbox.mode(AshMssql.TestRepo, :manual)
