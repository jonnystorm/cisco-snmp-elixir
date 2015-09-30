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
        SNMPMIB.Object.value(copy_state_object)
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
        SNMPMIB.Object.value(copy_fail_cause_object)
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
      _ ->
        if tries < 10 do
          :timer.sleep 500
          _await_copy_result(row, agent, credential, tries + 1)
        else
          {:error, :timeout}
        end
    end
  end
  defp await_copy_result(row, agent, credential) do
    _await_copy_result(row, agent, credential, 0)
  end

  defp destroy_copy_entry_row(row, agent, credential) do
    CcCopyEntry.ccCopyEntryRowStatus
    |> SNMPMIB.index(row)
    |> SNMPMIB.Object.value(6)
    |> NetSNMP.set(agent, credential)
  end

  defp has_an_empty_ccCopyFileName_value(copy_entry) do
    (copy_entry |> CcCopyEntry.ccCopyFileName |> SNMPMIB.Object.value) == ""
  end

  defp to_objects_for_ram_copy(copy_entry, row) do
    [
      copy_entry |> CcCopyEntry.ccCopySourceFileType |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyDestFileType |> SNMPMIB.index(row)
    ]
  end

  defp to_objects_for_non_ram_copy(copy_entry, row) do
    [
      copy_entry |> CcCopyEntry.ccCopyProtocol |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopySourceFileType |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyDestFileType |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyFileName |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyServerAddressType |> SNMPMIB.index(row),
      copy_entry |> CcCopyEntry.ccCopyServerAddressRev1 |> SNMPMIB.index(row)
    ]
  end

  defp to_objects(copy_entry, row) do
    if has_an_empty_ccCopyFileName_value(copy_entry) do
      to_objects_for_ram_copy(copy_entry, row)
    else
      to_objects_for_non_ram_copy(copy_entry, row)
    end
  end

  defp set_copy_entry_row(copy_entry, row, agent, credential) do
    copy_entry
    |> to_objects(row)
    |> NetSNMP.set(agent, credential)
  end

  defp set_copy_entry_row_status(copy_entry, row, agent, credential) do
    copy_entry
    |> CcCopyEntry.ccCopyEntryRowStatus
    |> SNMPMIB.index(row)
    |> NetSNMP.set(agent, credential)
  end

  defp process_copy_entry(copy_entry, agent, credential) do
    row = 800

    try do
      [{:ok, _}, {:ok, _}|_] = copy_entry
      |> set_copy_entry_row(row, agent, credential)

      [{:ok, _}] = copy_entry
      |> set_copy_entry_row_status(row, agent, credential)

      :ok = await_copy_result(row, agent, credential)

      :ok
    after
      destroy_copy_entry_row(row, agent, credential)
    end
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
