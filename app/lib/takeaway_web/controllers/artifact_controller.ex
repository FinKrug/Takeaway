defmodule TakeawayWeb.ArtifactController do
  use TakeawayWeb, :controller

  alias Takeaway.{Speeches, SpeechCreator}

  def show(conn, %{"id" => id}) do
    with {int, ""} <- Integer.parse(id),
         artifact when not is_nil(artifact) <- Speeches.get_artifact(int),
         stored when is_binary(stored) <- artifact.url,
         path = Path.join(SpeechCreator.uploads_dir(), Path.basename(stored)),
         true <- File.regular?(path) do
      send_download(conn, {:file, path}, filename: artifact.title || stored)
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
