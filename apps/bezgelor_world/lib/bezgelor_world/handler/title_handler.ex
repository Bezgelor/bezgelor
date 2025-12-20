defmodule BezgelorWorld.Handler.TitleHandler do
  @moduledoc """
  Handles title-related events and client requests.

  Titles are account-wide and unlocked through various achievements:
  - Reputation levels (reaching Exalted, etc.)
  - Achievement completions
  - Quest completions
  - Path progress

  ## Usage

  Called by other handlers when relevant events occur:

      TitleHandler.check_reputation_titles(conn_pid, account_id, faction_id, level)
      TitleHandler.check_achievement_titles(conn_pid, account_id, achievement_id)
  """

  alias BezgelorDb.Titles
  alias BezgelorData

  alias BezgelorProtocol.Packets.World.{
    ServerTitleList,
    ServerTitleUnlocked,
    ServerActiveTitleChanged
  }

  require Logger

  @doc """
  Send full title list to client (called on login).
  """
  @spec send_title_list(pid(), integer()) :: :ok
  def send_title_list(connection_pid, account_id) do
    titles = Titles.get_titles(account_id)
    active_title_id = Titles.get_active_title(account_id)

    packet = %ServerTitleList{
      active_title_id: active_title_id,
      titles: titles
    }

    send(connection_pid, {:send_packet, packet})
    :ok
  end

  @doc """
  Handle client request to set active title.
  """
  @spec handle_set_active_title(pid(), integer(), integer() | nil) :: :ok
  def handle_set_active_title(connection_pid, account_id, title_id) do
    case Titles.set_active_title(account_id, title_id) do
      {:ok, _account} ->
        packet = %ServerActiveTitleChanged{
          title_id: title_id,
          success: true
        }

        send(connection_pid, {:send_packet, packet})

        Logger.debug("Account #{account_id} set active title to #{inspect(title_id)}")

      {:error, :not_owned} ->
        packet = %ServerActiveTitleChanged{
          title_id: nil,
          success: false
        }

        send(connection_pid, {:send_packet, packet})

        Logger.warning("Account #{account_id} tried to use unowned title #{title_id}")

      {:error, reason} ->
        Logger.error("Failed to set active title: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Grant a title to an account and notify client.
  Returns :ok if granted, :already_owned if already has it.
  """
  @spec grant_title(pid(), integer(), integer()) :: :ok | :already_owned
  def grant_title(connection_pid, account_id, title_id) do
    case Titles.grant_title(account_id, title_id) do
      {:ok, title} ->
        packet = %ServerTitleUnlocked{
          title_id: title_id,
          unlocked_at: title.unlocked_at
        }

        send(connection_pid, {:send_packet, packet})

        Logger.info("Account #{account_id} unlocked title #{title_id}")
        :ok

      {:already_owned, _} ->
        :already_owned

      {:error, reason} ->
        Logger.error("Failed to grant title #{title_id}: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Check and grant reputation-based titles when a reputation level changes.
  Called by ReputationHandler when standing changes level.
  """
  @spec check_reputation_titles(pid(), integer(), integer(), atom()) :: :ok
  def check_reputation_titles(connection_pid, account_id, faction_id, new_level) do
    BezgelorData.titles_for_reputation(faction_id, new_level)
    |> Enum.each(fn title ->
      grant_title(connection_pid, account_id, title.id)
    end)

    :ok
  end

  @doc """
  Check and grant achievement-based titles when an achievement is completed.
  Called by AchievementHandler when achievement completes.
  """
  @spec check_achievement_titles(pid(), integer(), integer()) :: :ok
  def check_achievement_titles(connection_pid, account_id, achievement_id) do
    BezgelorData.titles_for_achievement(achievement_id)
    |> Enum.each(fn title ->
      grant_title(connection_pid, account_id, title.id)
    end)

    :ok
  end

  @doc """
  Check and grant quest-based titles when a quest is completed.
  Called by QuestHandler when quest completes.
  """
  @spec check_quest_titles(pid(), integer(), integer()) :: :ok
  def check_quest_titles(connection_pid, account_id, quest_id) do
    BezgelorData.titles_for_quest(quest_id)
    |> Enum.each(fn title ->
      grant_title(connection_pid, account_id, title.id)
    end)

    :ok
  end

  @doc """
  Check and grant path-based titles when path level increases.
  Called by PathHandler when path level increases.
  """
  @spec check_path_titles(pid(), integer(), String.t(), integer()) :: :ok
  def check_path_titles(connection_pid, account_id, path, new_level) do
    BezgelorData.titles_for_path(path, new_level)
    |> Enum.each(fn title ->
      grant_title(connection_pid, account_id, title.id)
    end)

    :ok
  end
end
