# Copyright © 2015 Jonathan Storm <the.jonathan.storm@gmail.com>
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the COPYING.WTFPL file for more details.

defmodule CiscoSNMP do
  alias CiscoConfigCopy.CcCopyEntry, as: CcCopyEntry

  defp get_copy_state(row, agent, credential) do
    result = CcCopyEntry.ccCopyState
      |> SNMPMIB.index(row)
      |> NetSNMP.get(agent, credential)

    case result do
      [ok: copy_state_object] ->
        copy_state_object
          |> SNMPMIB.Object.value
          |> String.to_integer
      [error: error] ->
        error
    end
  end

  defp get_copy_fail_cause(row, agent, credential) do
    result = CcCopyEntry.ccCopyFailCause
      |> SNMPMIB.index(row)
      |> NetSNMP.get(agent, credential)

    case result do
      [ok: copy_fail_cause_object] ->
        copy_fail_cause_object
          |> SNMPMIB.Object.value
          |> String.to_integer
      [error: _] ->
        nil
    end
  end

  defp _await_copy_result(row, agent, credential, tries) do
    case get_copy_state(row, agent, credential) do
      3 ->
        :ok
      4 ->
        fail_cause = get_copy_fail_cause(row, agent, credential)
          |> CiscoConfigCopy.typeConfigCopyFailCause

        {:error, fail_cause}
      error ->
        if tries < 3 do
          :timer.sleep 500 
          _await_copy_result(row, agent, credential, tries + 1)
        else
          {:error, error}
        end
    end 
  end
  defp await_copy_result(row, agent, credential) do
    _await_copy_result(row, agent, credential, 0)
  end

  defp destroy_copy_entry_row(row, agent, credential) do
    [ok: _] = CcCopyEntry.ccCopyEntryRowStatus
      |> SNMPMIB.index(row)
      |> SNMPMIB.Object.value(6)
      |> NetSNMP.set(agent, credential)
  end

  def create_copy_entry_row(copy_entry, row, agent, credential) do
    [
      copy_entry |> CcCopyEntry.ccCopyProtocol |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopySourceFileType |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyDestFileType |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyFileName |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyServerAddressType |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyServerAddressRev1 |> SNMPMIB.index(row),
    ] |> NetSNMP.set(agent, credential)

    copy_entry
      |> CcCopyEntry.ccCopyEntryRowStatus
      |> SNMPMIB.index(row)
      |> NetSNMP.set(agent, credential)

    row
  end

  defp process_copy_entry(copy_entry, agent, credential) do
    row = 800
    copy_entry |> create_copy_entry_row(row, agent, credential)
    :ok = await_copy_result(row, agent, credential)
    destroy_copy_entry_row(row, agent, credential)
  end

  def copy_tftp_run(tftp_server, file, agent, credential) do
    CiscoConfigCopy.cc_copy_entry(:tftp,
      :network_file, :running_config, file,
      :ipv4, tftp_server
    ) |> process_copy_entry(agent, credential)
  end

  def copy_run_start(agent, credential) do
    CiscoConfigCopy.cc_copy_entry(:running_config, :startup_config)
      |> process_copy_entry(agent, credential)
  end

  def copy_start_run(agent, credential) do
    CiscoConfigCopy.cc_copy_entry(:startup_config, :running_config)
      |> process_copy_entry(agent, credential)
  end
end
