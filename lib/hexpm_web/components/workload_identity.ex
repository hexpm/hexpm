defmodule HexpmWeb.Components.WorkloadIdentity do
  @moduledoc """
  Parts shared by the package and organization workload identity pages.
  """
  use Phoenix.Component

  import HexpmWeb.Components.Input, only: [errors: 1, translate_error: 1]

  alias Hexpm.WorkloadIdentities.TrustedRepository

  # Repositories past this many fold behind "and N more".
  @shown_repositories 4

  @doc """
  The GitHub workflows a workload identity trusts: its repositories, or every
  repository of its owner, then its workflow and environment.
  """
  attr :workload_identity, :map, required: true

  def trusted_workflows(assigns) do
    {shown, folded} = Enum.split(assigns.workload_identity.repositories, @shown_repositories)
    assigns = assign(assigns, shown: shown, folded: folded)

    ~H"""
    <div class="flex flex-col gap-1.5">
      <p
        :if={@workload_identity.repositories == []}
        class="text-sm text-grey-900 dark:text-white"
      >
        Every repository <span class="font-semibold">{@workload_identity.repository_owner}</span>
        has on GitHub
      </p>
      <div :if={@shown != [] and @folded == []} class="flex flex-wrap items-center gap-1.5">
        <.repository_chip :for={repository <- @shown} repository={repository} />
      </div>
      <details :if={@folded != []} class="group/repositories">
        <summary class="flex flex-wrap items-center gap-1.5 list-none cursor-default [&::-webkit-details-marker]:hidden">
          <.repository_chip :for={repository <- @shown} repository={repository} />
          <span class="text-xs font-medium text-primary-600 dark:text-primary-300 cursor-pointer hover:underline group-open/repositories:hidden">
            and {length(@folded)} more
          </span>
        </summary>
        <div class="mt-1.5 flex flex-wrap items-center gap-1.5">
          <.repository_chip :for={repository <- @folded} repository={repository} />
        </div>
      </details>
      <p class="text-xs text-grey-500 dark:text-grey-300">
        Workflow
        <span class="text-grey-900 dark:text-white">{workflow_label(@workload_identity.workflow)}</span>
        <span aria-hidden="true">&middot;</span>
        Environment
        <span class="text-grey-900 dark:text-white">
          {environment_label(@workload_identity.environment)}
        </span>
      </p>
    </div>
    """
  end

  attr :repository, TrustedRepository, required: true

  defp repository_chip(assigns) do
    ~H"""
    <span class="break-all rounded-md border border-grey-200 dark:border-grey-600 bg-grey-50 dark:bg-grey-900 px-1.5 py-0.5 font-mono text-xs text-grey-900 dark:text-grey-100">
      {@repository.name}
    </span>
    """
  end

  defp workflow_label(workflow) when workflow in [nil, ""], do: "any"
  defp workflow_label(workflow), do: workflow

  defp environment_label(environment) when environment in [nil, ""], do: "any"
  defp environment_label(environment), do: environment

  @doc """
  The repositories textarea. It shows what was submitted, or one repository
  name per line of the workload identity being edited.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :required, :boolean, default: false
  slot :help

  def repositories_input(assigns) do
    assigns =
      assign(assigns,
        id: Phoenix.HTML.Form.input_id(assigns.form, :repositories),
        name: Phoenix.HTML.Form.input_name(assigns.form, :repositories),
        placeholder: "widget\ngadget 123456",
        value: repositories_value(assigns.form),
        errors:
          assigns.form.errors |> Keyword.get_values(:repositories) |> Enum.map(&translate_error/1)
      )

    ~H"""
    <div>
      <label for={@id} class="block text-small font-medium text-grey-900 dark:text-grey-100 mb-[6px]">
        Repositories <span :if={@required} class="text-red-600 dark:text-red-400 ml-1">*</span>
      </label>
      <textarea
        id={@id}
        name={@name}
        rows="3"
        placeholder={@placeholder}
        class={[
          "w-full px-3 py-2.5 border rounded font-mono text-sm",
          "bg-white dark:bg-grey-800 text-grey-900 dark:text-grey-100",
          "placeholder:font-sans placeholder:text-grey-300 dark:placeholder:text-grey-400",
          "focus:outline-none focus:ring-1",
          @errors != [] &&
            "border-red-300 focus:border-red-600 focus:ring-red-600 dark:border-red-700",
          @errors == [] &&
            "border-grey-200 focus:border-primary-600 focus:ring-primary-600 dark:border-grey-600"
        ]}
      ><%= @value %></textarea>
      <.errors errors={@errors} />
      <div class="mt-1 text-xs text-grey-500 dark:text-grey-300">
        {render_slot(@help)}
      </div>
    </div>
    """
  end

  defp repositories_value(form) do
    case form.params do
      %{"repositories" => value} when is_binary(value) ->
        value

      _params ->
        form.data.repositories
        |> Enum.map(&TrustedRepository.short_name/1)
        |> Enum.join("\n")
    end
  end
end
