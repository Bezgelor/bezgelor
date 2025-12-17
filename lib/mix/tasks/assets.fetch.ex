defmodule Mix.Tasks.Assets.Fetch do
  @moduledoc """
  Fetches non-redistributable game assets from private storage.

  These assets (3D models, textures) are extracted from WildStar game files
  and cannot be committed to the repository. This task downloads them from
  your configured private storage location.

  ## Usage

      mix assets.fetch              # Fetch all assets
      mix assets.fetch --models     # Fetch only 3D models
      mix assets.fetch --textures   # Fetch only textures
      mix assets.fetch --dry-run    # Show what would be fetched

  ## Configuration

  Set the `BEZGELOR_ASSETS_URL` environment variable to your private storage URL:

      # S3 bucket
      export BEZGELOR_ASSETS_URL="s3://my-bucket/bezgelor-assets"

      # HTTPS endpoint
      export BEZGELOR_ASSETS_URL="https://my-server.com/assets"

      # Local/network path
      export BEZGELOR_ASSETS_URL="/mnt/assets/bezgelor"

  ## Asset Structure

  The remote storage should have this structure:

      bezgelor-assets/
        models/
          characters/
            human_male.glb
            human_female.glb
            ...
        textures/
          characters/
            Human/
              Male/
                *.png
              Female/
                *.png
            ...

  ## Extracting Assets

  To create these assets from your WildStar game client, see:
  docs/asset-extraction.md
  """

  use Mix.Task

  @shortdoc "Fetch game assets from private storage"

  @models_dest "apps/bezgelor_portal/priv/static/models/characters"
  @textures_dest "apps/bezgelor_portal/priv/static/textures"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [models: :boolean, textures: :boolean, dry_run: :boolean],
        aliases: [n: :dry_run]
      )

    assets_url = System.get_env("BEZGELOR_ASSETS_URL")

    if is_nil(assets_url) do
      Mix.shell().error("""
      BEZGELOR_ASSETS_URL environment variable not set.

      Set it to your private storage location:
        export BEZGELOR_ASSETS_URL="s3://my-bucket/bezgelor-assets"
        export BEZGELOR_ASSETS_URL="https://my-server.com/assets"
        export BEZGELOR_ASSETS_URL="/path/to/local/assets"

      See docs/asset-extraction.md for how to create these assets.
      """)

      exit({:shutdown, 1})
    end

    fetch_models = opts[:models] || (!opts[:models] && !opts[:textures])
    fetch_textures = opts[:textures] || (!opts[:models] && !opts[:textures])
    dry_run = opts[:dry_run] || false

    if dry_run do
      Mix.shell().info("Dry run mode - no files will be downloaded")
    end

    if fetch_models do
      fetch_assets(assets_url, "models/characters", @models_dest, dry_run)
    end

    if fetch_textures do
      fetch_assets(assets_url, "textures", @textures_dest, dry_run)
    end

    Mix.shell().info("Done!")
  end

  defp fetch_assets(base_url, source_path, dest_path, dry_run) do
    Mix.shell().info("Fetching #{source_path} -> #{dest_path}")

    cond do
      String.starts_with?(base_url, "s3://") ->
        fetch_from_s3(base_url, source_path, dest_path, dry_run)

      String.starts_with?(base_url, "http://") or String.starts_with?(base_url, "https://") ->
        fetch_from_http(base_url, source_path, dest_path, dry_run)

      true ->
        fetch_from_local(base_url, source_path, dest_path, dry_run)
    end
  end

  defp fetch_from_s3(base_url, source_path, dest_path, dry_run) do
    # Parse s3://bucket/prefix
    uri = URI.parse(base_url)
    bucket = uri.host
    prefix = String.trim_leading(uri.path || "", "/")
    full_prefix = Path.join([prefix, source_path])

    if dry_run do
      Mix.shell().info("  Would sync from s3://#{bucket}/#{full_prefix}/ to #{dest_path}/")
    else
      File.mkdir_p!(dest_path)

      cmd = "aws"
      args = ["s3", "sync", "s3://#{bucket}/#{full_prefix}/", "#{dest_path}/"]

      case System.cmd(cmd, args, stderr_to_stdout: true) do
        {output, 0} ->
          Mix.shell().info(output)

        {output, _} ->
          Mix.shell().error("S3 sync failed: #{output}")
          Mix.shell().info("Make sure AWS CLI is installed and configured")
      end
    end
  end

  defp fetch_from_http(base_url, source_path, dest_path, dry_run) do
    # For HTTP, we'd need a manifest file listing all assets
    # This is a scaffold - implement based on your HTTP server setup
    manifest_url = "#{base_url}/#{source_path}/manifest.txt"

    if dry_run do
      Mix.shell().info("  Would fetch manifest from #{manifest_url}")
      Mix.shell().info("  Would download files to #{dest_path}/")
    else
      Mix.shell().info("""
      HTTP fetch not fully implemented.

      Options:
      1. Create a manifest.txt at #{manifest_url} listing all files
      2. Use wget/curl: wget -r -np -nH --cut-dirs=2 #{base_url}/#{source_path}/ -P #{dest_path}
      3. Use rsync over SSH instead
      """)
    end
  end

  defp fetch_from_local(base_url, source_path, dest_path, dry_run) do
    source = Path.join(base_url, source_path)

    if dry_run do
      Mix.shell().info("  Would copy from #{source}/ to #{dest_path}/")
    else
      if File.dir?(source) do
        File.mkdir_p!(dest_path)

        case System.cmd("rsync", ["-av", "#{source}/", "#{dest_path}/"], stderr_to_stdout: true) do
          {output, 0} ->
            Mix.shell().info(output)

          {_, _} ->
            # Fallback to cp if rsync not available
            case System.cmd("cp", ["-r", "#{source}/.", dest_path], stderr_to_stdout: true) do
              {_, 0} -> Mix.shell().info("  Copied successfully")
              {output, _} -> Mix.shell().error("Copy failed: #{output}")
            end
        end
      else
        Mix.shell().error("Source directory not found: #{source}")
      end
    end
  end
end
