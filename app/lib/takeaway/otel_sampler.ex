defmodule Takeaway.OtelSampler do
  @moduledoc """
  OpenTelemetry root sampler: keeps every trace except Kubernetes probe requests.

  The kubelet calls `/healthz` and `/readyz` on every pod every few seconds
  (deploy/deployment.yaml). Tracing those would bury real requests in Dash0, so
  their root spans are dropped. Used as the `root` of a `parent_based` sampler
  (config/config.exs), so spans that continue an existing trace follow it.
  """

  @behaviour :otel_sampler

  @probe_paths ["/healthz", "/readyz"]

  @impl :otel_sampler
  def setup(_opts), do: %{}

  @impl :otel_sampler
  def description(_config), do: "TakeawayOtelSampler{drop=/healthz,/readyz}"

  @impl :otel_sampler
  def should_sample(ctx, _trace_id, _links, _span_name, _span_kind, attributes, _config) do
    tracestate = ctx |> :otel_tracer.current_span_ctx() |> :otel_span.tracestate()
    decision = if probe?(attributes), do: :drop, else: :record_and_sample
    {decision, [], tracestate}
  end

  defp probe?(attributes) when is_map(attributes),
    do: Map.get(attributes, :"url.path") in @probe_paths

  defp probe?(_attributes), do: false
end
