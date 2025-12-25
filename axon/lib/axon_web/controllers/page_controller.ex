defmodule AxonWeb.PageController do
  use AxonWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
