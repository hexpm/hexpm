defmodule HexpmWeb.OAuthView do
  use HexpmWeb, :view

  alias HexpmWeb.SharedAuthorizationView

  @doc """
  Delegates to SharedAuthorizationView for formatting scopes.
  """
  defdelegate format_scopes(scopes, format), to: SharedAuthorizationView

  @doc """
  Renders grouped scopes using SharedAuthorizationView with OAuth-specific styling.
  """
  def render_grouped_scopes(scopes, _with_checkboxes \\ true) when is_list(scopes) do
    SharedAuthorizationView.render_grouped_scopes(scopes, :oauth)
  end

  @doc """
  Prepares authorization data for the shared partial.
  """
  def authorization_assigns(
        _conn,
        client,
        redirect_uri,
        scopes,
        state,
        code_challenge,
        code_challenge_method
      ) do
    hidden_fields = [
      {"client_id", client.client_id},
      {"redirect_uri", redirect_uri},
      {"scope", Enum.join(scopes, " ")}
    ]

    hidden_fields =
      if state do
        [{"state", state} | hidden_fields]
      else
        hidden_fields
      end

    hidden_fields =
      if code_challenge do
        [{"code_challenge", code_challenge} | hidden_fields]
      else
        hidden_fields
      end

    hidden_fields =
      if code_challenge_method do
        [{"code_challenge_method", code_challenge_method} | hidden_fields]
      else
        hidden_fields
      end

    %{
      client_name: client.name,
      scopes: scopes,
      render_scopes: &render_grouped_scopes(&1, true),
      format_summary: &format_scopes(&1, :summary),
      form_action: ~p"/oauth/authorize",
      hidden_fields: hidden_fields,
      approve_value: "approve",
      deny_value: "deny",
      with_checkboxes: true
    }
  end
end
