defmodule TakeawayWeb.PageController do
  use TakeawayWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
