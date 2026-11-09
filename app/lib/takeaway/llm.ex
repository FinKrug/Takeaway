defmodule Takeaway.LLM do
  @moduledoc """
  Text-generation behaviour used for post-speech summaries. Choose the
  implementation with `config :takeaway, :llm, MyModule`. The default,
  `Takeaway.LLM.Disabled`, returns `{:error, :disabled}` and callers fall back
  to a plain extractive summary.
  """
  @callback complete(system :: String.t(), prompt :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  def complete(system, prompt, opts \\ []), do: impl().complete(system, prompt, opts)
  def impl, do: Application.get_env(:takeaway, :llm, Takeaway.LLM.Disabled)
  def name, do: inspect(impl())
end

defmodule Takeaway.LLM.Disabled do
  @moduledoc false
  @behaviour Takeaway.LLM
  @impl true
  def complete(_system, _prompt, _opts), do: {:error, :disabled}
end
