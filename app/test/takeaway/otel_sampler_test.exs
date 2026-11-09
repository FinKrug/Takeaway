defmodule Takeaway.OtelSamplerTest do
  # Uses the global tracer provider configured in config/config.exs and
  # config/test.exs, so these tests also check that the sampler is wired in.
  use ExUnit.Case, async: false

  require OpenTelemetry.Tracer, as: Tracer
  require Record

  @span_fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @span_fields)

  setup do
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
    :ok
  end

  test "Kubernetes probe requests are not traced" do
    for path <- ["/healthz", "/readyz"] do
      Tracer.with_span :GET, %{kind: :server, attributes: %{"url.path": path}} do
        Tracer.with_span "takeaway.repo.query", %{} do
          :ok
        end
      end
    end

    refute_receive {:span, _}, 200
  end

  test "other requests are traced along with their child spans" do
    Tracer.with_span :GET, %{kind: :server, attributes: %{"url.path": "/speeches/new"}} do
      Tracer.with_span "takeaway.repo.query", %{} do
        :ok
      end
    end

    assert_receive {:span, span(name: "takeaway.repo.query")}
    assert_receive {:span, span(name: :GET)}
  end
end
