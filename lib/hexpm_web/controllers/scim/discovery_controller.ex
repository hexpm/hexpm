defmodule HexpmWeb.SCIM.DiscoveryController do
  use HexpmWeb, :controller

  import HexpmWeb.SCIMHelpers

  @user_schema "urn:ietf:params:scim:schemas:core:2.0:User"
  @list_schema "urn:ietf:params:scim:api:messages:2.0:ListResponse"

  # Static conformance surface. Okta and Entra read these to decide which
  # requests to send; the values assert what the Users resource implements.
  def service_provider_config(conn, _params) do
    scim_json(conn, 200, %{
      "schemas" => ["urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"],
      "documentationUri" => "https://hex.pm/docs/organization-sso",
      "patch" => %{"supported" => true},
      "bulk" => %{"supported" => false, "maxOperations" => 0, "maxPayloadSize" => 0},
      "filter" => %{"supported" => true, "maxResults" => 200},
      "changePassword" => %{"supported" => false},
      "sort" => %{"supported" => false},
      "etag" => %{"supported" => false},
      "authenticationSchemes" => [
        %{
          "type" => "oauthbearertoken",
          "name" => "OAuth Bearer Token",
          "description" => "Bearer token generated on the organization's SSO dashboard"
        }
      ],
      "meta" => %{"resourceType" => "ServiceProviderConfig"}
    })
  end

  def resource_types(conn, _params) do
    scim_json(conn, 200, %{
      "schemas" => [@list_schema],
      "totalResults" => 1,
      "startIndex" => 1,
      "itemsPerPage" => 1,
      "Resources" => [
        %{
          "schemas" => ["urn:ietf:params:scim:schemas:core:2.0:ResourceType"],
          "id" => "User",
          "name" => "User",
          "endpoint" => "/Users",
          "schema" => @user_schema,
          "meta" => %{"resourceType" => "ResourceType"}
        }
      ]
    })
  end

  def schemas(conn, _params) do
    scim_json(conn, 200, %{
      "schemas" => [@list_schema],
      "totalResults" => 1,
      "startIndex" => 1,
      "itemsPerPage" => 1,
      "Resources" => [
        %{
          "schemas" => ["urn:ietf:params:scim:schemas:core:2.0:Schema"],
          "id" => @user_schema,
          "name" => "User",
          "description" => "Organization member",
          "attributes" => [
            %{
              "name" => "userName",
              "type" => "string",
              "multiValued" => false,
              "required" => true,
              "caseExact" => false,
              "mutability" => "readWrite",
              "returned" => "default",
              "uniqueness" => "server"
            },
            %{
              "name" => "active",
              "type" => "boolean",
              "multiValued" => false,
              "required" => false,
              "mutability" => "readWrite",
              "returned" => "default"
            },
            %{
              "name" => "displayName",
              "type" => "string",
              "multiValued" => false,
              "required" => false,
              "caseExact" => false,
              "mutability" => "readOnly",
              "returned" => "default",
              "uniqueness" => "none"
            },
            %{
              "name" => "emails",
              "type" => "complex",
              "multiValued" => true,
              "required" => false,
              "mutability" => "readOnly",
              "returned" => "default",
              "subAttributes" => [
                %{
                  "name" => "value",
                  "type" => "string",
                  "multiValued" => false,
                  "required" => false,
                  "caseExact" => false,
                  "mutability" => "readOnly",
                  "returned" => "default"
                },
                %{
                  "name" => "primary",
                  "type" => "boolean",
                  "multiValued" => false,
                  "required" => false,
                  "mutability" => "readOnly",
                  "returned" => "default"
                }
              ]
            }
          ],
          "meta" => %{"resourceType" => "Schema"}
        }
      ]
    })
  end

  def not_found(conn, _params) do
    scim_error(conn, 404, "Not found")
  end
end
