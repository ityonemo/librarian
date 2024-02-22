defmodule SSH.Key do
  @moduledoc """
  provides a basic way to generate passwordless SSH key files.
  More complex options should be implemented directly via the
  `:public_key` module.
  """

  require Record

  Record.defrecord(:private_rsa, :RSAPrivateKey, [
    :version,
    :modulus,
    :publicExponent,
    :privateExponent,
    :prime1,
    :prime2,
    :exponent1,
    :exponent2,
    :coefficient,
    :otherPrimeInfos
  ])

  Record.defrecord(:private_ec, :ECPrivateKey, [
    :version,
    :privateKey,
    :parameters,
    :publicKey
  ])

  @typedoc """
  currently, rsa is the only mode supported.  In the future, ec mode might
  be added.
  """
  @type mode :: :rsa

  @spec gen(mode, userinfo :: String.t(), keyword) ::
          {pub :: String.t(), priv :: String.t()}
  @doc """
  roughly equivalent to the shell command `ssh-keygen -t rsa`.  Appends
  `userinfo` in the comments field.

  returns `{public_key, private_key}`

  As is expected by openssh, the `public_key` is ssh-encoded and the
  `private_key` is pem-encoded.

  ## options
  - `:size` - sets the bit size.  for rsa, this can be 2048 or 4096
  """
  def gen(:rsa, userinfo, opts \\ []) do
    # destructure important parts out of the private key for public key generation.
    size = opts[:size] || 2048

    private_key =
      private_rsa(modulus: modulus, publicExponent: exponent) =
      :public_key.generate_key({:rsa, size, 3})

    public_key = {:RSAPublicKey, modulus, exponent}

    {encode(public_key, userinfo), encode(private_key)}
  end

  defp encode(key) do
    :public_key.pem_encode([:public_key.pem_entry_encode(elem(key, 0), key)])
  end

  defp encode(key, email) do
    :ssh_file.encode([{key, comment: email}], :auth_keys)
  end
end
