defmodule HexpmWeb.PackageWorkloadIdentityView do
  use HexpmWeb, :view
  import HexpmWeb.Components.PackageLayout
  import HexpmWeb.Components.Badge, only: [badge: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  import HexpmWeb.Components.WorkloadIdentity,
    only: [repositories_input: 1, trusted_workflows: 1]
end
