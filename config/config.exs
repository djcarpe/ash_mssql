import Config

if Mix.env() == :dev do
  config :git_ops,
    mix_project: AshMssql.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/ash-project/ash_mssql",
    # Instructs the tool to manage your mix version in your `mix.exs` file
    # See below for more information
    manage_mix_version?: true,
    # Instructs the tool to manage the version in your README.md
    # Pass in `true` to use `"README.md"` or a string to customize
    manage_readme_version: [
      "README.md",
      "documentation/tutorials/getting-started-with-ash-mssql.md"
    ],
    version_tag_prefix: "v"
end

if Mix.env() == :test do
  config :ash, :validate_domain_resource_inclusion?, false
  config :ash, :validate_domain_config_inclusion?, false

  config :ash_mssql, AshMssql.TestRepo,
    username: "sa",
    database: "ash_mssql_test",
    hostname: "localhost",
    port: 1433,
    log_stacktrace_mfa: fn t, _, _ -> t end,
    pool: Ecto.Adapters.SQL.Sandbox,
    # sobelow_skip ["Config.Secrets"]
    password: System.get_env("TDS_PASSWORD") || "YourStrong@Passw0rd"

  config :ash_mssql, AshMssql.TestRepo, migration_primary_key: [name: :id, type: :binary_id]

  config :ash_mssql, AshMssql.TestNoSandboxRepo,
    username: "sa",
    database: "ash_mssql_test",
    hostname: "localhost",
    port: 1433

  # sobelow_skip ["Config.Secrets"]
  config :ash_mssql, AshMssql.TestNoSandboxRepo, password: System.get_env("TDS_PASSWORD") || "YourStrong@Passw0rd"

  config :ash_mssql, AshMssql.TestNoSandboxRepo,
    migration_primary_key: [name: :id, type: :binary_id]

  # ecto_repos: [AshMssql.TestRepo, AshMssql.TestNoSandboxRepo],
  config :ash_mssql,
    ecto_repos: [AshMssql.TestRepo],
    ash_domains: [
      AshMssql.Test.Domain
    ]

  config :logger, level: :warning
end
