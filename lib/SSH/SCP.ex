defmodule SSH.SCP do
  @moduledoc false
end

defmodule SSH.SCP.FatalError do
  defexception message: "fatal error"
end

defmodule SSH.SCP.Error do
  defexception message: "generic scp error"
end
