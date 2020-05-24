defmodule SSH.ClientIdentity do

  @moduledoc """
  implements erlang's `:ssh_client_key_api` behaviour so that you can log in
  using a pem key, instead of the default id_rsa private/public pair.  It's
  pretty hard to believe that this is not an option, but there you go.
  """

  @behaviour :ssh_client_key_api

  # SUPPORT SKEW IN THE SSH API ACROSS OTP RELEASES.
  case :otp_release |> :erlang.system_info |> :string.to_integer do
    {n, []} when n >= 23 ->
      @impl true
      defdelegate add_host_key(host, port, key, opts), to: :ssh_file
      @impl true
      defdelegate is_host_key(key, host, port, alg, opts), to: :ssh_file
      defp valid_key(key, algorithm) do
        :ssh_transport.valid_key_sha_alg(:private, key, algorithm)
      end
    _ ->
      @impl true
      defdelegate add_host_key(host, key, opts), to: :ssh_file
      @impl true
      defdelegate is_host_key(key, host, alg, opts), to: :ssh_file
      defp valid_key(key, algorithm) do
        :ssh_transport.valid_key_sha_alg(key, algorithm)
      end
  end

  @impl true
  @spec user_key(:ssh.pubkey_alg, keyword) ::
    {:ok, :public_Key.private_key} |
    {:error, any}
  def user_key(algorithm, connect_options) do
    password =
      Keyword.get(connect_options,
        identity_pass_phrase(algorithm),
        :ignore)

    # retrieve the identity option that was stashed in the
    # callback option.  Erlang helpfully puts that into "key_cb_private"
    # field of the list.

    with prv_opts when not is_nil(prv_opts) <- Keyword.get(connect_options, :key_cb_private),
         identity when not is_nil(identity) <- Keyword.get(prv_opts, :identity),
         {:ok, pem_bin}                     <- File.read(identity),
         {:ok, key}                         <- decode(pem_bin, password),
         true                               <- valid_key(key, algorithm) do
      {:ok, key}
    else
      nil ->   {:error, :bad_options}
      false -> {:error, :bad_keytype_in_file}
      err -> err
    end
  end

  # shamelessly stolen from erlang:ssh_file
  defp identity_pass_phrase('ssh-dss'       ), do: :dsa_pass_phrase
  defp identity_pass_phrase('ssh-rsa'       ), do: :rsa_pass_phrase
  defp identity_pass_phrase('rsa-sha2-256'  ), do: :rsa_pass_phrase
  defp identity_pass_phrase('rsa-sha2-384'  ), do: :rsa_pass_phrase
  defp identity_pass_phrase('rsa-sha2-512'  ), do: :rsa_pass_phrase
  ## Not yet implemented: identity_pass_phrase("ssh-ed25519"   ) -> ed25519_pass_phrase;
  ## Not yet implemented: identity_pass_phrase("ssh-ed448"     ) -> ed448_pass_phrase;
  defp identity_pass_phrase('ecdsa-sha2-' ++ _), do: :ecdsa_pass_phrase
  defp identity_pass_phrase(a) when is_atom(a) do
    identity_pass_phrase(Atom.to_charlist(a))
  end
  defp identity_pass_phrase(_), do: raise "unknown algorithm error"

  @spec decode(binary, charlist) ::
    {:ok, :public_key.private_key} |
    {:error, any}
  defp decode(pem_bin, password) do
    case :public_key.pem_decode(pem_bin) do
      [entry = {_, _, :not_encrypted}] ->
        {:ok, :public_key.pem_entry_decode(entry)}
      [entry] when password != :ignore ->
        {:ok, :public_key.pem_entry_decode(entry, password)}
      _ ->
        {:error, :no_passphrase}
    end
  end

end
