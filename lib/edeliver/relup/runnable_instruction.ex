defmodule Edeliver.Relup.RunnableInstruction do
  @moduledoc """
    This module can be used to provide custom instructions
    to modify the relup. They can be used the the implementation
    of the Edeliver.Relup.Modifcation module. A runnable instruction
    must implement a `run/1` function which will be executed
    during the upgrade on the nodes.

    Example:

      defmodule Acme.Relup.PingNodeInstruction do
        use Edeliver.Relup.RunnableInstruction

        def modify_relup(instructions = %Instructions{up_instructions: up_instructions}, _config = %Config{}) do
          node_name = :"node@host"
          %{instructions|
            up_instructions:   [call_this([node_name]) | instructions.up_instructions],
            down_instructions: [call_this([node_name]) | instructions.down_instructions]
          }
        end

        # executed during hot code upgrade from relup file
        def run(_options = [node_name]) do
          :net_adm.ping(node_name)
        end

        # actually implemented already in this module
        def call_this(arguments) do
          # creates a relup instruction to call `run/1` of this module
          {:apply, {__MODULE__, :run, arguments}}
        end

      end

      # using the instruction
      defmodule Acme.Relup.Modification do
        use Edeliver.Relup.Modification

        def modify_relup(instructions = %Instructions{}, _config = %Config{}) do
          instructions |> Edeliver.Relup.DefaultModification.modify_relup(Config) # use default modifications
                       |> Acme.Relup.PingNodeInstruction.modify_relup(Config) # apply also custom instructions
        end
      end

  """
  use Behaviour

  @doc """
    The function to run during hot code upgrade on nodes.
    If it throws an error before the `point_of_no_return` the
    upgrade is aborted. If it throws an error and was executed
    after that point, the release is restarted
  """
  @callback run(options::[term]) :: :ok

  @doc """
    Returns a function which inserts the relup instruction that calls
    the `run/1` fuction of this module. Default is inserting it at the
    end of the instructions
  """
  @callback insert_where() :: ((%Edeliver.Relup.Instructions{}, Edeliver.Relup.Instruction.instruction) -> %Edeliver.Relup.Instructions{})

  @doc """
    Returns the arguments which will be passed the `run/1` function during the upgrade.
    Default is an empty list.
  """
  @callback arguments(instructions::%Edeliver.Relup.Instructions{}, config::%ReleaseManager.Config{}) :: [term]

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Edeliver.Relup.Instruction
      @behaviour Edeliver.Relup.RunnableInstruction
      alias Edeliver.Relup.Instructions
      alias ReleaseManager.Config
      require Logger

      def modify_relup(instructions = %Instructions{}, config = %Config{}) do
        call_this_instruction = call_this(arguments(instructions, config))
        insert_where_fun = insert_where
        instructions |> insert_where_fun.(call_this_instruction)
                     |> ensure_module_loaded_before_instruction(call_this_instruction)
      end

      def arguments(%Edeliver.Relup.Instructions{}, %ReleaseManager.Config{}), do: []

      def insert_where, do: &append/2

      defoverridable [modify_relup: 2, insert_where: 0, arguments: 2]

      @doc """
        Calls the `run/1` function of this module from the
        relup file during hot code upgrade
      """
      @spec call_this(arguments::[term]) :: instruction|instructions
      def call_this(arguments \\ []) do
        {:apply, {__MODULE__, :run, [arguments]}}
      end

      @doc """
        Logs an error using the `Logger` on the running node which is upgraded.
        In addition the same error message is logged on the node which executes
        the upgrade and is displayed as output of the
        `$APP/bin/$APP upgarde $RELEASE` command.
      """
      @spec error(message::String.t) :: no_return
      def error(message) do
        Logger.error message
        log_in_upgrade_script(:error, message)
      end

      @doc """
        Logs a warning using the `Logger` on the running node which is upgraded.
        In addition the same warning message is logged on the node which executes
        the upgrade and is displayed as output of the
        `$APP/bin/$APP upgarde $RELEASE` command.
      """
      @spec warn(message::String.t) :: no_return
      def warn(message) do
        Logger.warn message
        log_in_upgrade_script(:warning, message)
      end

      @doc """
        Logs an info message using the `Logger` on the running node which is upgraded.
        In addition the same info message is logged on the node which executes
        the upgrade and is displayed as output of the
        `$APP/bin/$APP upgarde $RELEASE` command.
      """
      @spec info(message::String.t) :: no_return
      def info(message) do
        Logger.info message
        log_in_upgrade_script(:info, message)
      end

       @doc """
        Logs a debug message using the `Logger` on the running node which is upgraded.
        In addition the same debug message is logged on the node which executes
        the upgrade and is displayed as output of the
        `$APP/bin/$APP upgarde $RELEASE` command.
      """
      @spec debug(message::String.t) :: no_return
      def debug(message) do
        Logger.debug message
        log_in_upgrade_script(:debug, message)
      end





      @privdoc """
        Logs the message of the given type on the node which executes
        the upgrade and displays it as output of the
        `$APP/bin/$APP upgarde $RELEASE` command. The message is prefixed
        with a string drived from the message type.
      """
      @spec log_in_upgrade_script(type:: :error|:warning|:info|:debug, message::String.t) :: no_return
      defp log_in_upgrade_script(type, message) do
        message = String.to_char_list(message)
        prefix = case type do
          :error   -> '--> X '
          :warning -> '--> ! '
          :info    -> '--> '
          _        -> '---> ' # debug
        end
        :erlang.nodes |> Enum.filter(fn node ->
          Regex.match?(~r/upgrader_\d+/, Atom.to_string(node))
        end) |> Enum.each(fn node ->
          :rpc.cast(node, :io, :format, [:user, '~s~s~n', [prefix, message]])
        end)
      end

    end # quote

  end # defmacro __using__


end