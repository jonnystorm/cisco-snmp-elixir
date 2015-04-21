# Copyright © 2015 Jonathan Storm <the.jonathan.storm@gmail.com>
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the COPYING.WTFPL file for more details.

defmodule CiscoSNMP do
  alias SNMPMIB.Cisco.CiscoConfigCopy, as: CiscoConfigCopy
  alias CiscoConfigCopy.CcCopyEntry, as: CcCopyEntry

  defp get_copy_state(row, agent, credential) do
    result = CcCopyEntry.ccCopyState
      |> NetSNMP.index(row)
      |> NetSNMP.get(agent, credential)

    case result do
      [ok: copy_state_object] ->
        copy_state_object
          |> NetSNMP.Object.value
          |> String.to_integer
      [error: _] ->
        nil
    end
  end

  defp get_copy_fail_cause(row, agent, credential) do
    result = CcCopyEntry.ccCopyFailCause
      |> NetSNMP.index(row)
      |> NetSNMP.get(agent, credential)

    case result do
      [ok: copy_fail_cause_object] ->
        copy_fail_cause_object
          |> NetSNMP.Object.value
          |> String.to_integer
      [error: _] ->
        nil
    end
  end

  defp await_copy_result(row, agent, credential) do
    case get_copy_state(row, agent, credential) do
      3 ->
        :ok
      4 ->
        fail_cause = get_copy_fail_cause(row, agent, credential)
          |> CcCopyEntry.typeConfigCopyFailCause

        {:error, fail_cause}
      _ ->
        :timer.sleep 500 
        await_copy_result(row, agent, credential)
    end 
  end

  defp destroy_copy_entry_row(row, agent, credential) do
    [ok: _] = CcCopyEntry.ccCopyEntryRowStatus
      |> NetSNMP.index(row)
      |> NetSNMP.Object.value(6)
      |> NetSNMP.set(agent, credential)
  end

  defp create_copy_entry_row(copy_entry, row, agent, credential) do
    [
      copy_entry |> CcCopyEntry.ccCopyProtocol |> NetSNMP.index(row),
      CcCopyEntry.ccCopySourceFileType(copy_entry) |> NetSNMP.index(row),
      CcCopyEntry.ccCopyDestFileType(copy_entry) |> NetSNMP.index(row),
      CcCopyEntry.ccCopyFileName(copy_entry) |> NetSNMP.index(row),
      CcCopyEntry.ccCopyServerAddressType(copy_entry) |> NetSNMP.index(row),
      CcCopyEntry.ccCopyServerAddressRev1(copy_entry) |> NetSNMP.index(row),
      CcCopyEntry.ccCopyEntryRowStatus(copy_entry) |> NetSNMP.index(row)
    ] |> NetSNMP.set(agent, credential)

    row
  end

  def copy_tftp_run(tftp_server, file, agent, credential) do
    row = 800
    
    CiscoConfigCopy.cc_copy_entry(:tftp,
      :network_file, :running_config, file,
      :ipv4, tftp_server
    ) |> create_copy_entry_row(row, agent, credential)
    
    :ok = await_copy_result(row, agent, credential)
    destroy_copy_entry_row(row, agent, credential)
  end
end
