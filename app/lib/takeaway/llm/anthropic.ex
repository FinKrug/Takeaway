defmodule Takeaway.LLM.Anthropic do
  @moduledoc """
  Anthropic Messages API client. Enabled when `ANTHROPIC_API_KEY` is set
  (see config/runtime.exs); `ANTHROPIC_MODEL` overrides the model.
  """
  @behaviour Takeaway.LLM

  @url ~c"https://api.anthropic.com/v1/messages"

  @impl true
  def complete(system, prompt, opts) do
    cfg = Application.get_env(:takeaway, __MODULE__, [])
    key = Keyword.fetch!(cfg, :api_key)
    model = Keyword.get(opts, :model) || Keyword.get(cfg, :model, "claude-sonnet-4-5")

    body =
      Jason.encode!(%{
        model: model,
        max_tokens: Keyword.get(opts, :max_tokens, 1024),
        system: system,
        messages: [%{role: "user", content: prompt}]
      })

    headers = [
      {~c"x-api-key", String.to_charlist(key)},
      {~c"anthropic-version", ~c"2023-06-01"}
    ]

    http_opts = [
      timeout: 60_000,
      ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
    ]

    case :httpc.request(:post, {@url, headers, ~c"application/json", body}, http_opts,
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _, resp}} -> parse(resp)
      {:ok, {{_, status, _}, _, resp}} -> {:error, {:http, status, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def parse(json) do
    case Jason.decode(json) do
      {:ok, %{"content" => blocks}} when is_list(blocks) ->
        text = for %{"type" => "text", "text" => t} <- blocks, into: "", do: t
        if String.trim(text) == "", do: {:error, :empty}, else: {:ok, String.trim(text)}

      _ ->
        {:error, :bad_response}
    end
  end
end
