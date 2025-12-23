defmodule BezgelorPortal.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    # Database is in bezgelor_db umbrella app
    Application.fetch_env!(:bezgelor_db, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(:bezgelor_db)
  end
end
