defmodule Spoker.Auth do
  require HTTPoison

  @sso_base_url Application.fetch_env!(:spoker, :sso_base_url)
  @sso_client_secret Application.fetch_env!(:spoker, :sso_client_secret)

  def exchange(auth_code) do
    url = "#{@sso_base_url}/token"
    body = Jason.encode!(
      %{
        auth_code: auth_code,
        client_secret: @sso_client_secret
      }
    )

    response = HTTPoison.post!(url, body, [{"Content-Type", "application/json"}])

    if response.status_code == 200 do
      response = Jason.decode!(response.body)
      {:ok, response["access_token"]}
    else
      {:err, response.status_code}
    end
  end

  def inspect(token) do
    url = "#{@sso_base_url}/inspect"
    body = Jason.encode!(
      %{
        access_token: token,
      }
    )

    response = HTTPoison.post!(url, body, [{"Content-Type", "application/json"}])

    if response.status_code == 200 do
      response = Jason.decode!(response.body)
      {:ok, response["username"]}
    else
      {:err, response.status_code}
    end
  end
end
