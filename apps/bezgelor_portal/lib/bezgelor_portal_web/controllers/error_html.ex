defmodule BezgelorPortalWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use BezgelorPortalWeb, :html

  # Custom error pages
  embed_templates "error_html/*"

  # Fallback for any other error templates
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
