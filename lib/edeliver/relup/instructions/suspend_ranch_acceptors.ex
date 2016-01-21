defmodule Edeliver.Relup.Instructions.SuspendRanchAcceptors do
  @moduledoc """
    This upgrade instruction suspends the ranch acceptors to
    avoid that new connections will be accepted. It will be
    inserted right after the "point of no return". When the
    upgrade is done, the

      `Edeliver.Relup.Instructions.SuspendRanchAcceptors`

    instruction reenables the acceptors again. To make sure
    that the ranch acceptors are found, use this instruciton
    after the

      `Edeliver.Relup.Instructions.CheckRanchAcceptors`

    instruction which will abort the upgrade if the acceptors
    cannot be found. Because real suspending of ranch acceptors
    is not possible because ranch acceptors do not handle sys
    messages, they are actually terminated. In addition the ranch
    acceptor supervisor is suspended to avoid starting new acceptors.
    Use the

      `Edeliver.Relup.Instructions.ResumeRanchAcceptors`

    instruction at the end of your instruction list to reenable
    accepting tcp connection when the upgrade is done.

  """
  use Edeliver.Relup.RunnableInstruction
  alias Edeliver.Relup.Instructions.CheckRanchAcceptors

  @doc """
    Appends the instruction to the instruction after the
    "point of no return" but before any instruction which
    loads or unloads new code, (re-)starts or stops
    any running processes, or (re-)starts or stops any
    application or the emulator.
  """
  def insert_where, do: &append_after_point_of_no_return/2

  @doc """
    Returns name of the application. This name is taken as argument
    for the `run/1` function and is required to access the acceptor processes
    through the supervision tree
  """
  def arguments(_instructions = %Instructions{}, _config = %Config{name: name}) do
    name |> String.to_atom
  end

  @doc """
    Suspends all ranch acceptors to avoid handling new requests / connections
    during the upgrade. Because suspending of ranch acceptors is not possible
    they are terminated. In addition the ranch acceptor supervisor is suspended
    to avoid starting new acceptors.
  """
  @spec run(otp_application_name::atom) :: :ok
  def run(otp_application_name) do
    info "Suspending ranch socket acceptors..."
    ranch_listener_sup = CheckRanchAcceptors.ranch_listener_sup(otp_application_name)
    assume true = is_pid(ranch_listener_sup), "Failed to suspend ranch socket acceptors. Ranch listener supervisor not found."
    ranch_acceptors_sup = CheckRanchAcceptors.ranch_acceptors_sup(ranch_listener_sup)
    assume true = is_pid(ranch_acceptors_sup), "Failed to suspend ranch socket acceptors. Ranch acceptors supervisor not found."
    assume [_|_] = acceptors = CheckRanchAcceptors.ranch_acceptors(ranch_acceptors_sup), "Failed to suspend ranch socket acceptors. No acceptor processes found."
    acceptors_count = Enum.count(acceptors)
    info "Stopping #{inspect acceptors_count} ranch socket acceptors..."
    assume true = Enum.all?(acceptors, fn acceptor ->
      Supervisor.terminate_child(ranch_acceptors_sup, acceptor) == :ok
    end), "Failed to suspend ranch socket acceptors."
    info "Suspended #{inspect acceptors_count} ranch acceptors."
    info "Suspending ranch socket acceptor supervisor..."
    assume :ok = :sys.suspend(ranch_acceptors_sup), "Failed to suspend ranch socket acceptor supervisor."
  end



end
