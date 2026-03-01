defmodule VerdantWeb.PageController do
  use VerdantWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
