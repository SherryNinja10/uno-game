defmodule UnoGameWeb.PageController do
  use UnoGameWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
