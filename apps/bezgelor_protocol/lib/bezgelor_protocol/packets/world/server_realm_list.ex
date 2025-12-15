defmodule BezgelorProtocol.Packets.World.ServerRealmList do
  @moduledoc """
  Realm list response for the character select screen.

  ## Overview

  Sent in response to ClientRealmList when the player clicks "Change Realm"
  on the character select screen. Contains information about available realms
  and their status.

  ## Packet Structure

  ```
  unused             : uint64           - Unused field
  realm_count        : uint32           - Number of realms
  realms             : RealmInfo[]      - Realm entries
  message_count      : uint32           - Number of server messages
  messages           : ServerMessage[]  - Server message entries
  ```

  ## RealmInfo Structure

  ```
  realm_id           : uint32           - Realm ID
  realm_name         : wide_string      - Realm display name
  note_string_id     : uint32           - String ID for realm note (0 for none)
  flags              : uint32           - Realm flags (e.g., FactionRestricted = 0x10)
  type               : 2 bits           - 0=PVE, 1=PVP
  status             : 3 bits           - 0=Unknown, 1=Offline, 2=Down, 3=Standby, 4=Up
  population         : 3 bits           - 0=Low, 1=Medium, 2=High, 3=Full
  unused1            : uint32           - Unused
  unused2            : 16 bytes         - Unused
  account_realm_data : AccountRealmData - Account-specific realm info
  unused3-6          : uint16 x 4       - Unused
  ```

  ## AccountRealmData Structure

  ```
  realm_id              : 14 bits     - Realm ID
  character_count       : uint32      - Number of characters on realm
  last_played_character : wide_string - Name of last played character
  last_played_time      : uint64      - Timestamp of last play
  ```

  ## ServerMessage Structure

  ```
  index         : uint32           - Message index
  message_count : 8 bits           - Number of message strings
  messages      : wide_string[]    - Message text strings
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Realm type constants
  @realm_type_pve 0
  @realm_type_pvp 1

  # Realm status constants
  @realm_status_unknown 0
  @realm_status_offline 1
  @realm_status_down 2
  @realm_status_standby 3
  @realm_status_up 4

  # Realm population constants
  @realm_population_low 0
  @realm_population_medium 1
  @realm_population_high 2
  @realm_population_full 3

  defstruct unused: 0,
            realms: [],
            messages: []

  defmodule RealmInfo do
    @moduledoc """
    Information about a single realm.
    """
    defstruct realm_id: 1,
              realm_name: "Bezgelor",
              note_string_id: 0,
              flags: 0,
              type: 0,
              status: 4,
              population: 0,
              unused1: 0,
              unused2: <<0::128>>,
              account_realm_data: nil,
              unused3: 0,
              unused4: 0,
              unused5: 0,
              unused6: 0

    @type t :: %__MODULE__{
            realm_id: non_neg_integer(),
            realm_name: String.t(),
            note_string_id: non_neg_integer(),
            flags: non_neg_integer(),
            type: non_neg_integer(),
            status: non_neg_integer(),
            population: non_neg_integer(),
            unused1: non_neg_integer(),
            unused2: binary(),
            account_realm_data: AccountRealmData.t() | nil,
            unused3: non_neg_integer(),
            unused4: non_neg_integer(),
            unused5: non_neg_integer(),
            unused6: non_neg_integer()
          }
  end

  defmodule AccountRealmData do
    @moduledoc """
    Account-specific data for a realm.
    """
    defstruct realm_id: 1,
              character_count: 0,
              last_played_character: "",
              last_played_time: 0

    @type t :: %__MODULE__{
            realm_id: non_neg_integer(),
            character_count: non_neg_integer(),
            last_played_character: String.t(),
            last_played_time: non_neg_integer()
          }
  end

  defmodule ServerMessage do
    @moduledoc """
    A server message displayed in the realm list.
    """
    defstruct index: 0,
              messages: []

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            messages: [String.t()]
          }
  end

  @type t :: %__MODULE__{
          unused: non_neg_integer(),
          realms: [RealmInfo.t()],
          messages: [ServerMessage.t()]
        }

  @impl true
  def opcode, do: :server_realm_list

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    # Unused (uint64)
    writer = PacketWriter.write_uint64_bits(writer, packet.unused)

    # Realm count and realms
    writer = PacketWriter.write_uint32_bits(writer, length(packet.realms))
    writer = Enum.reduce(packet.realms, writer, &write_realm_info/2)

    # Message count and messages
    writer = PacketWriter.write_uint32_bits(writer, length(packet.messages))
    writer = Enum.reduce(packet.messages, writer, &write_server_message/2)

    # Flush remaining bits
    writer = PacketWriter.flush_bits(writer)

    {:ok, writer}
  end

  # Write a single RealmInfo entry
  defp write_realm_info(realm, writer) do
    account_data = realm.account_realm_data || %AccountRealmData{realm_id: realm.realm_id}

    # RealmId (uint32)
    writer = PacketWriter.write_uint32_bits(writer, realm.realm_id)

    # RealmName (wide string)
    writer = PacketWriter.write_wide_string(writer, realm.realm_name || "")

    # NoteStringId (uint32)
    writer = PacketWriter.write_uint32_bits(writer, realm.note_string_id)

    # Flags (uint32)
    writer = PacketWriter.write_uint32_bits(writer, realm.flags)

    # Type (2 bits), Status (3 bits), Population (3 bits)
    writer = PacketWriter.write_bits(writer, realm.type, 2)
    writer = PacketWriter.write_bits(writer, realm.status, 3)
    writer = PacketWriter.write_bits(writer, realm.population, 3)

    # Unused1 (uint32)
    writer = PacketWriter.write_uint32_bits(writer, realm.unused1)

    # Unused2 (16 bytes = 128 bits) - use write_bytes_bits to maintain bit stream
    # Ensure we write exactly 16 bytes
    unused2 = realm.unused2 || <<0::128>>
    # Pad or truncate to exactly 16 bytes
    unused2 = :binary.part(<<unused2::binary, 0::128>>, 0, 16)
    writer = PacketWriter.write_bytes_bits(writer, unused2)

    # AccountRealmData
    writer = write_account_realm_data(account_data, writer)

    # Unused3-6 (4 x uint16)
    writer = PacketWriter.write_bits(writer, realm.unused3, 16)
    writer = PacketWriter.write_bits(writer, realm.unused4, 16)
    writer = PacketWriter.write_bits(writer, realm.unused5, 16)
    PacketWriter.write_bits(writer, realm.unused6, 16)
  end

  # Write AccountRealmData
  defp write_account_realm_data(data, writer) do
    # RealmId (14 bits)
    writer = PacketWriter.write_bits(writer, data.realm_id, 14)

    # CharacterCount (uint32)
    writer = PacketWriter.write_uint32_bits(writer, data.character_count)

    # LastPlayedCharacter (wide string)
    writer = PacketWriter.write_wide_string(writer, data.last_played_character || "")

    # LastPlayedTime (uint64)
    PacketWriter.write_uint64_bits(writer, data.last_played_time)
  end

  # Write a ServerMessage entry
  defp write_server_message(message, writer) do
    # Index (uint32)
    writer = PacketWriter.write_uint32_bits(writer, message.index)

    # Message count (8 bits)
    writer = PacketWriter.write_bits(writer, length(message.messages), 8)

    # Messages (wide strings)
    Enum.reduce(message.messages, writer, fn msg, w ->
      PacketWriter.write_wide_string(w, msg)
    end)
  end

  @doc """
  Build a realm list packet from configuration.

  ## Options

  - `:character_count` - Number of characters on the realm (default: 0)
  - `:last_played_character` - Name of last played character (default: "")
  - `:last_played_time` - Timestamp of last play (default: 0)
  """
  @spec from_config(keyword()) :: t()
  def from_config(opts \\ []) do
    realm_config = Application.get_env(:bezgelor_realm, :realm_list, [])

    # Build realm info from config
    realms = build_realms_from_config(realm_config, opts)

    # Server messages (empty by default)
    messages = Keyword.get(realm_config, :messages, [])

    %__MODULE__{
      unused: 0,
      realms: realms,
      messages: build_messages(messages)
    }
  end

  @doc """
  Build a realm list from database realm records.

  ## Parameters

  - `realms` - List of Realm database records
  - `account_id` - Account ID for character counts
  - `current_realm_id` - ID of the current realm (for status)

  ## Options

  - `:get_character_count` - Function to get character count (arity 2: account_id, realm_id)
  - `:get_last_played` - Function to get last played info (arity 2: account_id, realm_id)
  """
  @spec from_realms([map()], integer(), integer(), keyword()) :: t()
  def from_realms(realms, account_id, current_realm_id, opts \\ []) do
    get_character_count = Keyword.get(opts, :get_character_count, fn _a, _r -> 0 end)
    get_last_played = Keyword.get(opts, :get_last_played, fn _a, _r -> {"", 0} end)

    realm_infos =
      Enum.map(realms, fn realm ->
        char_count = get_character_count.(account_id, realm.id)
        {last_char, last_time} = get_last_played.(account_id, realm.id)

        # Current realm is always "Up", others depend on online status
        status =
          cond do
            realm.id == current_realm_id -> @realm_status_up
            realm.online -> @realm_status_up
            true -> @realm_status_offline
          end

        %RealmInfo{
          realm_id: realm.id,
          realm_name: realm.name,
          note_string_id: realm.note_text_id || 0,
          flags: realm.flags || 0,
          type: realm_type_to_int(realm.type),
          status: status,
          population: @realm_population_low,
          account_realm_data: %AccountRealmData{
            realm_id: realm.id,
            character_count: char_count,
            last_played_character: last_char || "",
            last_played_time: last_time || 0
          }
        }
      end)

    %__MODULE__{
      unused: 0,
      realms: realm_infos,
      messages: []
    }
  end

  @doc """
  Build a simple single-realm list from the bezgelor_realm config.
  """
  @spec single_realm(keyword()) :: t()
  def single_realm(opts \\ []) do
    # Read from bezgelor_realm config
    realm_id = Application.get_env(:bezgelor_realm, :realm_id, 1)
    realm_name = Application.get_env(:bezgelor_realm, :realm_name, "Bezgelor")
    realm_type = Application.get_env(:bezgelor_realm, :realm_type, :pve)
    realm_flags = Application.get_env(:bezgelor_realm, :realm_flags, 0)
    note_string_id = Application.get_env(:bezgelor_realm, :realm_note_text_id, 0)

    type_value = realm_type_to_int(realm_type)

    character_count = Keyword.get(opts, :character_count, 0)
    last_played_character = Keyword.get(opts, :last_played_character, "")
    last_played_time = Keyword.get(opts, :last_played_time, 0)

    realm_info = %RealmInfo{
      realm_id: realm_id,
      realm_name: realm_name,
      note_string_id: note_string_id,
      flags: realm_flags,
      type: type_value,
      status: @realm_status_up,
      population: @realm_population_low,
      account_realm_data: %AccountRealmData{
        realm_id: realm_id,
        character_count: character_count,
        last_played_character: last_played_character,
        last_played_time: last_played_time
      }
    }

    %__MODULE__{
      unused: 0,
      realms: [realm_info],
      messages: []
    }
  end

  # Build realms from configuration
  defp build_realms_from_config([], opts) do
    # No explicit realm_list config, use single realm from bezgelor_realm config
    [single_realm(opts).realms |> List.first()]
  end

  defp build_realms_from_config(config, opts) when is_list(config) do
    realms = Keyword.get(config, :realms, [])

    if realms == [] do
      build_realms_from_config([], opts)
    else
      Enum.map(realms, fn realm_config ->
        build_realm_from_config(realm_config, opts)
      end)
    end
  end

  defp build_realm_from_config(config, opts) do
    realm_id = Keyword.get(config, :id, 1)

    %RealmInfo{
      realm_id: realm_id,
      realm_name: Keyword.get(config, :name, "Bezgelor"),
      note_string_id: Keyword.get(config, :note_string_id, 0),
      flags: Keyword.get(config, :flags, 0),
      type: realm_type_to_int(Keyword.get(config, :type, :pve)),
      status: realm_status_to_int(Keyword.get(config, :status, :up)),
      population: realm_population_to_int(Keyword.get(config, :population, :low)),
      account_realm_data: %AccountRealmData{
        realm_id: realm_id,
        character_count: Keyword.get(opts, :character_count, 0),
        last_played_character: Keyword.get(opts, :last_played_character, ""),
        last_played_time: Keyword.get(opts, :last_played_time, 0)
      }
    }
  end

  defp build_messages([]), do: []

  defp build_messages(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.map(fn {msg, idx} ->
      %ServerMessage{
        index: idx,
        messages: List.wrap(msg)
      }
    end)
  end

  # Convert realm type atom to integer
  defp realm_type_to_int(:pve), do: @realm_type_pve
  defp realm_type_to_int(:pvp), do: @realm_type_pvp
  defp realm_type_to_int(type) when is_integer(type), do: type
  defp realm_type_to_int(_), do: @realm_type_pve

  # Convert realm status atom to integer
  defp realm_status_to_int(:unknown), do: @realm_status_unknown
  defp realm_status_to_int(:offline), do: @realm_status_offline
  defp realm_status_to_int(:down), do: @realm_status_down
  defp realm_status_to_int(:standby), do: @realm_status_standby
  defp realm_status_to_int(:up), do: @realm_status_up
  defp realm_status_to_int(status) when is_integer(status), do: status
  defp realm_status_to_int(_), do: @realm_status_up

  # Convert realm population atom to integer
  defp realm_population_to_int(:low), do: @realm_population_low
  defp realm_population_to_int(:medium), do: @realm_population_medium
  defp realm_population_to_int(:high), do: @realm_population_high
  defp realm_population_to_int(:full), do: @realm_population_full
  defp realm_population_to_int(pop) when is_integer(pop), do: pop
  defp realm_population_to_int(_), do: @realm_population_low
end
