defmodule HexpmWeb.Dashboard.Policy.Components.PolicyEdit do
  @moduledoc """
  Edit view for a single dependency policy.

  A policy is configured per repository: one tab for `hexpm` (public packages)
  and one for the organization's own repository. Each tab carries a restriction
  (cooldown / advisory / retirement) applied to every release in that
  repository, plus overrides that take priority over the restriction.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  alias Hexpm.Repository.OrganizationPolicy
  alias Phoenix.HTML.Form

  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]

  import HexpmWeb.Components.Input,
    only: [
      errors: 1,
      field_errors: 2,
      text_input: 1,
      textarea_input: 1
    ]

  import HexpmWeb.ViewIcons, only: [icon: 3]
  import HexpmWeb.ViewHelpers, only: [human_relative_time_from_now_text: 1]

  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :policy, :map, required: true
  attr :changeset, :any, required: true
  attr :paid?, :boolean, default: false
  attr :activity, :list, default: []
  attr :rev, :integer, default: 0

  def policy_edit(assigns) do
    ~H"""
    <div
      id="policy-edit-state"
      phx-hook="PolicyDirtyState"
      data-status-target="policy-save-state"
      class="space-y-6"
    >
      <a
        href={~p"/dashboard/orgs/#{@organization}/policies"}
        class="inline-flex items-center gap-1 text-sm text-grey-600 dark:text-grey-300 hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
      >
        {icon(:heroicon, "chevron-left", class: "w-4 h-4", width: 16, height: 16)} All policies
      </a>

      <.sudo_form
        :let={f}
        current_user={@current_user}
        for={@changeset}
        as={:policy}
        action={~p"/dashboard/orgs/#{@organization}/policies/#{@policy.name}"}
      >
        <div class="space-y-4">
          <.policy_header
            form={f}
            organization={@organization}
            policy={@policy}
            paid?={@paid?}
            rev={@rev}
          />

          <.description_card form={f} />

          <.resolution_flow />

          <.repository_rules_section form={f} organization={@organization} />

          <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div class="flex items-center gap-3">
              <.button type="submit" variant="primary">Save policy</.button>
              <a
                href={~p"/dashboard/orgs/#{@organization}/policies/#{@policy.name}"}
                class="text-sm font-medium text-grey-600 dark:text-grey-300 hover:text-grey-900 dark:hover:text-white"
              >
                Discard changes
              </a>
            </div>
            <span
              id="policy-save-state"
              class="text-xs text-grey-500 dark:text-grey-400"
              data-clean-text="All changes saved"
              data-dirty-text="Unsaved changes"
              aria-live="polite"
            >
              All changes saved
            </span>
          </div>
        </div>
      </.sudo_form>

      <.delete_policy_modal
        current_user={@current_user}
        organization={@organization}
        policy={@policy}
      />
    </div>
    """
  end

  attr :form, :any, required: true
  attr :organization, :map, required: true

  defp repository_rules_section(assigns) do
    assigns =
      assigns
      |> assign(:repositories, assigns.form[:repositories].value || [])
      |> assign(:private?, Form.input_value(assigns.form, :visibility) == "private")

    ~H"""
    <div class="space-y-4">
      <h3 class="sr-only">Repository rules</h3>
      <div id="repo-config" phx-hook="PrivateRepoTabs" class="space-y-4">
        <.repo_tabs repositories={@repositories} private?={@private?} />
        <%= inputs_for @form, :repositories, fn rf -> %>
          <.repo_panel
            form={rf}
            active?={repo_index(rf) == 0}
            organization={@organization}
          />
        <% end %>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :organization, :map, required: true
  attr :policy, :map, required: true
  attr :paid?, :boolean, required: true
  attr :rev, :integer, required: true

  defp policy_header(assigns) do
    assigns =
      assigns
      |> assign(:visibility, visibility_value(assigns.form, assigns.policy))
      |> assign(:name_errors, field_errors(assigns.form, :name))
      |> assign(:visibility_errors, field_errors(assigns.form, :visibility))

    ~H"""
    <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-4 sm:p-6">
      <input
        type="hidden"
        id={Form.input_id(@form, :visibility)}
        name={Form.input_name(@form, :visibility)}
        value={@visibility}
      />
      <div class="flex items-center gap-3">
        <div class="w-7 h-10 flex items-center justify-center flex-shrink-0 text-primary-600 dark:text-primary-300">
          {icon(:heroicon, "shield-check",
            class: "w-5 h-5 sm:w-6 sm:h-6",
            width: 24,
            height: 24
          )}
        </div>
        <div class="min-w-0 flex-1">
          <input
            id={Form.input_id(@form, :name)}
            name={Form.input_name(@form, :name)}
            value={Form.input_value(@form, :name)}
            required
            placeholder="strict-prod"
            class={[
              "w-full bg-transparent border-0 p-0 text-grey-900 dark:text-white",
              "text-xl sm:text-2xl font-bold leading-none font-mono",
              "focus:outline-none focus:ring-0 placeholder:text-grey-300 dark:placeholder:text-grey-500"
            ]}
          />
          <.errors errors={@name_errors} />
        </div>

        <div class="hidden sm:flex items-center gap-2 flex-shrink-0">
          <.visibility_control
            id="policy-visibility-tabs"
            target_id={Form.input_id(@form, :visibility)}
            paid?={@paid?}
            visibility={@visibility}
          />
          <.header_action
            id="policy-rename-action"
            class="rename-policy-btn"
            phx-hook="FocusFirstField"
            data-target="policy_name"
            label="Rename"
            icon="pencil"
            variant="neutral"
          />
          <.header_action
            class="delete-policy-header-btn"
            phx-click={show_modal("delete-policy-modal")}
            label="Delete"
            icon="trash"
            variant="danger"
          />
        </div>
      </div>

      <div class="grid grid-cols-1 sm:hidden gap-2 mt-4">
        <.visibility_control
          id="policy-visibility-tabs-mobile"
          target_id={Form.input_id(@form, :visibility)}
          paid?={@paid?}
          visibility={@visibility}
        />
      </div>
      <div class="grid grid-cols-2 sm:hidden gap-2 mt-2">
        <.header_action
          id="policy-rename-action-mobile"
          class="rename-policy-btn justify-center"
          phx-hook="FocusFirstField"
          data-target="policy_name"
          label="Rename"
          icon="pencil"
          variant="neutral"
        />
        <.header_action
          class="delete-policy-header-btn justify-center"
          phx-click={show_modal("delete-policy-modal")}
          label="Delete"
          icon="trash"
          variant="danger"
        />
      </div>
      <.errors errors={@visibility_errors} />

      <div class="border-t border-grey-100 dark:border-grey-700 mt-3 pt-3 flex flex-wrap items-center gap-x-3 gap-y-2 text-xs text-grey-500 dark:text-grey-400">
        <span>{length(@policy.repositories)} repositories</span>
        <span aria-hidden="true">·</span>
        <span>Updated {human_relative_time_from_now_text(@policy.updated_at)}</span>
        <span aria-hidden="true">·</span>
        <span>
          {visibility_description(@visibility)}
        </span>
        <span aria-hidden="true">·</span>
        <span>Admin role required to edit</span>
        <span aria-hidden="true">·</span>
        <span class="font-mono">rev {@rev}</span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :target_id, :string, required: true
  attr :paid?, :boolean, required: true
  attr :visibility, :string, required: true

  defp visibility_control(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="ToggleGroup"
      data-target={@target_id}
      class="inline-flex w-fit max-w-full justify-self-start rounded-lg border border-grey-200 dark:border-grey-700 bg-grey-50 dark:bg-grey-900 p-0.5"
    >
      <.visibility_button value="private" active?={@visibility == "private"} disabled={!@paid?}>
        {icon(:heroicon, "lock-closed", class: "w-3.5 h-3.5", width: 14, height: 14)} Private
      </.visibility_button>
      <.visibility_button value="public" active?={@visibility == "public"}>
        {icon(:heroicon, "globe-alt", class: "w-3.5 h-3.5", width: 14, height: 14)} Public
      </.visibility_button>
    </div>
    """
  end

  attr :value, :string, required: true
  attr :active?, :boolean, default: false
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  defp visibility_button(assigns) do
    ~H"""
    <button
      type="button"
      data-value={@value}
      data-active={@active? && "true"}
      disabled={@disabled}
      class={[
        "inline-flex items-center justify-center gap-1.5 h-8 px-3 rounded-md text-sm font-medium transition-colors",
        "text-grey-600 dark:text-grey-300 hover:text-grey-900 dark:hover:text-white",
        "data-[active=true]:bg-white dark:data-[active=true]:bg-grey-700",
        "data-[active=true]:text-grey-900 dark:data-[active=true]:text-white",
        "data-[active=true]:shadow-sm disabled:cursor-not-allowed disabled:opacity-45"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :form, :any, required: true

  defp description_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden">
      <div class="flex items-start gap-3 px-4 sm:px-6 py-4 border-b border-grey-100 dark:border-grey-700">
        <span class="w-[26px] h-[26px] rounded-md bg-grey-100 dark:bg-grey-700 text-grey-500 dark:text-grey-300 flex items-center justify-center flex-shrink-0">
          {icon(:heroicon, "pencil", class: "w-4 h-4", width: 14, height: 14)}
        </span>
        <div>
          <h3 class="text-grey-900 dark:text-white text-base font-semibold">Description</h3>
          <p class="text-sm text-grey-500 dark:text-grey-300 mt-0.5">
            Shown on the policy list and in the audit log.
          </p>
        </div>
      </div>
      <div class="p-4">
        <.textarea_input
          field={@form[:description]}
          placeholder="What this policy enforces"
          rows="3"
        />
      </div>
    </div>
    """
  end

  # Collapsible explainer of how a release is resolved against a tab.
  defp resolution_flow(assigns) do
    ~H"""
    <details class="group bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg shadow-sm overflow-hidden">
      <summary class="flex items-center gap-3 p-4 cursor-pointer list-none select-none hover:bg-grey-50 dark:hover:bg-grey-700/40 transition-colors">
        <span class="w-[26px] h-[26px] rounded-md bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-200 flex items-center justify-center flex-shrink-0">
          {icon(:heroicon, "square-3-stack-3d", class: "w-5 h-5", width: 20, height: 20)}
        </span>
        <span class="text-sm font-semibold text-grey-900 dark:text-white flex-1">
          How resolution works
        </span>
        <span class="text-grey-400 dark:text-grey-300 transition-transform group-open:rotate-180">
          {icon(:heroicon, "chevron-down", class: "w-4 h-4", width: 16, height: 16)}
        </span>
      </summary>
      <div class="px-4 pb-4 border-t border-grey-100 dark:border-grey-700 pt-4 bg-white dark:bg-grey-800">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <.flow_step number="1" title="Overrides" tone="primary">
            Checked first. <strong>Allow</strong>
            installs the release and skips the restriction; <strong>Deny</strong>
            blocks it. The most specific version requirement wins.
          </.flow_step>
          <.flow_step number="2" title="Restriction" tone="grey">
            Every other release must clear the cooldown, advisory, and retirement limits set for the repository.
          </.flow_step>
        </div>
        <p class="text-xs text-grey-500 dark:text-grey-300 mt-3">
          Releases already in a project's lockfile are trusted and never filtered.
        </p>
      </div>
    </details>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :tone, :string, default: "grey"
  slot :inner_block, required: true

  defp flow_step(assigns) do
    ~H"""
    <div class="flex items-start gap-3 rounded-lg border border-grey-200 dark:border-grey-700 bg-grey-50/70 dark:bg-grey-900/30 p-3">
      <span class={[
        "w-6 h-6 rounded-md flex items-center justify-center text-xs font-bold tabular-nums flex-shrink-0",
        @tone == "primary" &&
          "bg-primary-50 text-primary-700 dark:bg-primary-900/30 dark:text-primary-200",
        @tone == "grey" && "bg-grey-100 text-grey-600 dark:bg-grey-700 dark:text-grey-200"
      ]}>
        {@number}
      </span>
      <div>
        <div class="text-sm font-semibold text-grey-900 dark:text-white">{@title}</div>
        <p class="text-xs text-grey-500 dark:text-grey-300 mt-0.5">{render_slot(@inner_block)}</p>
      </div>
    </div>
    """
  end

  attr :repositories, :list, required: true
  attr :private?, :boolean, required: true

  defp repo_tabs(assigns) do
    tabs =
      assigns.repositories
      |> Enum.with_index()
      |> Enum.map(fn {repo, index} ->
        meta =
          repo
          |> repo_label()
          |> repo_meta()
          |> Map.put(:summary, repo_summary(repo))

        {meta, index}
      end)

    assigns = assign(assigns, :tabs, tabs)

    ~H"""
    <div
      id="repo-tabs"
      phx-hook="ToggleGroup"
      data-panel-container="#repo-config"
      class="grid grid-cols-1 lg:grid-cols-2 gap-3"
      role="tablist"
    >
      <button
        :for={{meta, index} <- @tabs}
        type="button"
        role="tab"
        data-value={meta.label}
        data-active={index == 0 && "true"}
        data-private-only={meta.kind == :org && "true"}
        hidden={meta.kind == :org and not @private?}
        class={[
          "group flex items-start gap-3 p-3 rounded-lg text-left border transition-colors cursor-pointer",
          "bg-white dark:bg-grey-800 border-grey-200 dark:border-grey-700",
          "hover:border-grey-300 dark:hover:border-grey-600",
          "data-[active=true]:border-primary-600 data-[active=true]:text-primary-700",
          "dark:data-[active=true]:text-primary-200 data-[active=true]:bg-primary-50 dark:data-[active=true]:bg-primary-900/20",
          "data-[active=true]:ring-2 data-[active=true]:ring-primary-100 dark:data-[active=true]:ring-primary-900/40"
        ]}
      >
        <span class={[
          "w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0",
          "bg-grey-100 text-grey-500 dark:bg-grey-700 dark:text-grey-300",
          "group-data-[active=true]:bg-primary-100 group-data-[active=true]:text-primary-700",
          "dark:group-data-[active=true]:bg-primary-900/40 dark:group-data-[active=true]:text-primary-200"
        ]}>
          {icon(:heroicon, repo_icon(meta.kind), class: "w-4 h-4", width: 16, height: 16)}
        </span>
        <span class="min-w-0 flex-1">
          <span class="flex items-center gap-2">
            <span class="font-mono text-sm font-semibold text-grey-800 dark:text-grey-100">
              {meta.label}
            </span>
            <span class="text-[10px] font-semibold uppercase tracking-wide text-grey-400 dark:text-grey-500 bg-grey-100 dark:bg-grey-700 rounded-full px-2 py-0.5">
              {repo_kind_label(meta.kind)}
            </span>
          </span>
          <span class="block text-xs text-grey-500 dark:text-grey-300 mt-1 truncate">
            {meta.summary}
          </span>
        </span>
      </button>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :active?, :boolean, required: true
  attr :organization, :map, required: true

  defp repo_panel(assigns) do
    assigns = assign(assigns, :meta, repo_meta(Form.input_value(assigns.form, :repository)))

    ~H"""
    <div data-panel={@meta.label} hidden={!@active?} class="space-y-4">
      <%= for {name, value} <- repo_hidden_fields(@form) do %>
        <input type="hidden" name={name} value={value} />
      <% end %>

      <div class="flex items-start gap-2 text-sm text-grey-500 dark:text-grey-300">
        {icon(:heroicon, repo_icon(@meta.kind), class: "w-4 h-4 mt-0.5", width: 16, height: 16)}
        <span>
          Settings for <code class="font-mono">{@meta.label}</code>. {@meta.desc}.
        </span>
      </div>

      <.restrictions_card form={@form} repo={@meta.label} />
      <.overrides_card form={@form} repo={@meta.label} organization={@organization} />
    </div>
    """
  end

  attr :form, :any, required: true
  attr :repo, :string, required: true

  defp restrictions_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg overflow-hidden">
      <div class="flex items-start gap-3 px-4 sm:px-6 py-4 border-b border-grey-100 dark:border-grey-700">
        <span class="w-[26px] h-[26px] rounded-md bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-200 flex items-center justify-center flex-shrink-0">
          {icon(:heroicon, "clock", class: "w-4 h-4", width: 14, height: 14)}
        </span>
        <div>
          <h4 class="text-grey-900 dark:text-white text-base font-semibold">Restrictions</h4>
          <p class="text-sm text-grey-500 dark:text-grey-300 mt-0.5">
            Limits applied to every release from <code class="font-mono">{@repo}</code>. Overrides skip them.
          </p>
        </div>
      </div>

      <div class="px-4 sm:px-6 py-2">
        <.cooldown_rule form={@form} />
        <.advisory_rule form={@form} />
        <.retirement_rule form={@form} />
      </div>
    </div>
    """
  end

  attr :form, :any, required: true

  defp cooldown_rule(assigns) do
    assigns =
      assigns
      |> assign(:cooldown_id, Form.input_id(assigns.form, :cooldown))
      |> assign(:cooldown_name, Form.input_name(assigns.form, :cooldown))
      |> assign(:cooldown_value, Form.input_value(assigns.form, :cooldown))

    ~H"""
    <.rule_block
      id={@cooldown_id <> "-rule"}
      title="Cooldown"
      icon="clock"
      icon_color="text-grey-500"
      description="Hold back releases until they reach a minimum age."
      enabled?={present?(@cooldown_value)}
    >
      <div class="grid gap-2 sm:flex sm:flex-wrap sm:items-center">
        <input
          type="text"
          id={@cooldown_id}
          name={@cooldown_name}
          value={@cooldown_value}
          placeholder="14d"
          class={[
            "h-9 px-3 border rounded text-sm font-mono w-28",
            "bg-white dark:bg-grey-800 text-grey-900 dark:text-grey-100",
            "border-grey-200 focus:border-primary-600 focus:ring-primary-600 dark:border-grey-600",
            "focus:outline-none focus:ring-1"
          ]}
        />
        <span class="text-xs leading-5 text-grey-500 dark:text-grey-300">
          days (<code class="font-mono">d</code>) · weeks (<code class="font-mono">w</code>) · months (<code class="font-mono">mo</code>)
        </span>
      </div>
    </.rule_block>
    """
  end

  attr :form, :any, required: true

  defp advisory_rule(assigns) do
    assigns =
      assigns
      |> assign(:advisory_id, Form.input_id(assigns.form, :advisory_min_severity))
      |> assign(:advisory_name, Form.input_name(assigns.form, :advisory_min_severity))
      |> assign(:advisory_value, Form.input_value(assigns.form, :advisory_min_severity))

    ~H"""
    <.rule_block
      id={@advisory_id <> "-rule"}
      title="Advisory"
      icon="exclamation-triangle"
      icon_color="text-yellow-500"
      description="Block any release with an advisory at or above the selected severity."
      enabled?={!is_nil(@advisory_value)}
    >
      <div class="grid gap-2 text-sm text-grey-500 dark:text-grey-300 sm:flex sm:flex-wrap sm:items-center">
        <span>Block releases with an advisory of</span>
        <.severity_select
          id={@advisory_id}
          name={@advisory_name}
          value={@advisory_value}
        />
      </div>
    </.rule_block>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, required: true

  defp severity_select(assigns) do
    assigns =
      assigns
      |> assign(:value_string, to_string(assigns.value || ""))
      |> assign(:dot_class, severity_dot_class(assigns.value))

    ~H"""
    <span class="relative inline-flex w-full sm:w-auto items-center" data-severity-select>
      <span
        data-severity-dot
        class={["pointer-events-none absolute left-2.5 size-2 rounded-full", @dot_class]}
      >
      </span>
      <select
        id={@id}
        name={@name}
        data-severity-control
        class={[
          "h-8 w-full sm:w-36 pl-6 pr-7 rounded-md border text-sm font-medium appearance-none",
          "bg-white dark:bg-grey-800 text-grey-900 dark:text-grey-100",
          "border-grey-200 focus:border-primary-600 focus:ring-primary-600 dark:border-grey-600",
          "focus:outline-none focus:ring-1"
        ]}
      >
        <option value="" selected={@value_string == ""}>Severity</option>
        <option
          :for={{label, value} <- severity_select_options()}
          value={value}
          selected={@value_string == to_string(value)}
        >
          {label}
        </option>
      </select>
      <span class="pointer-events-none absolute right-2 text-grey-500 dark:text-grey-300">
        {icon(:heroicon, "chevron-down", class: "w-3.5 h-3.5", width: 14, height: 14)}
      </span>
    </span>
    """
  end

  attr :form, :any, required: true

  defp retirement_rule(assigns) do
    assigns =
      assigns
      |> assign(:retirement_name, Form.input_name(assigns.form, :retirement_reasons))
      |> assign(:selected, selected_retirement_reasons(assigns.form))

    ~H"""
    <.rule_block
      id={Form.input_id(@form, :retirement_reasons) <> "-rule"}
      title="Retirement"
      icon="x-mark"
      icon_color="text-red-500"
      description="Block releases the author has retired for the selected reasons."
      enabled?={@selected != []}
      disabled_text="Retired releases are allowed"
    >
      <input type="hidden" name={@retirement_name <> "[]"} value="" />
      <div class="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap">
        <.retirement_checkbox
          :for={{label, value, _subtitle} <- retirement_reason_options()}
          name={@retirement_name <> "[]"}
          label={label}
          value={value}
          active?={value in @selected}
        />
      </div>
    </.rule_block>
    """
  end

  attr :form, :any, required: true
  attr :repo, :string, required: true
  attr :organization, :map, required: true

  defp overrides_card(assigns) do
    assigns =
      assigns
      |> assign(:overrides, Form.input_value(assigns.form, :overrides) || [])
      |> assign(:override_name, Form.input_name(assigns.form, :overrides))
      |> assign(:override_id, Form.input_id(assigns.form, :overrides))

    assigns =
      assigns
      |> assign(
        :package_suggestions_url,
        ~p"/dashboard/orgs/#{assigns.organization}/policies/package-suggestions?#{[repository: assigns.repo]}"
      )
      |> assign(
        :version_suggestions_url,
        ~p"/dashboard/orgs/#{assigns.organization}/policies/version-suggestions?#{[repository: assigns.repo]}"
      )

    ~H"""
    <div
      id={@override_id <> "-card"}
      phx-hook="OverrideList"
      data-package-suggestions-url={@package_suggestions_url}
      data-version-suggestions-url={@version_suggestions_url}
      class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg"
    >
      <div class="flex items-start gap-3 px-4 sm:px-6 py-4 border-b border-grey-100 dark:border-grey-700 bg-white dark:bg-grey-800 rounded-t-lg">
        <span class="w-[26px] h-[26px] rounded-md bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-200 flex items-center justify-center flex-shrink-0">
          {icon(:heroicon, "shield-check", class: "w-4 h-4", width: 14, height: 14)}
        </span>
        <div>
          <h4 class="text-grey-900 dark:text-white text-base font-semibold inline-flex items-center gap-2">
            Overrides
            <span class="text-[11px] font-semibold uppercase tracking-wide text-yellow-900 dark:text-yellow-200 bg-yellow-100 dark:bg-yellow-900/50 border border-yellow-200 dark:border-yellow-800 rounded px-1.5 py-0.5">
              skips restrictions
            </span>
          </h4>
          <p class="text-sm text-grey-500 dark:text-grey-300 mt-0.5">
            Allow or deny single packages. Overrides take priority over the restrictions above.
          </p>
        </div>
      </div>

      <div class="p-4 sm:p-6">
        <div class="flex items-start gap-2 rounded-lg border border-yellow-300 dark:border-yellow-700 bg-yellow-100/70 dark:bg-yellow-900/30 p-3 mb-4 text-sm text-yellow-900 dark:text-yellow-100">
          {icon(:heroicon, "exclamation-triangle",
            class: "w-4 h-4 flex-shrink-0 mt-0.5",
            width: 16,
            height: 16
          )}
          <span>
            An <strong>Allow</strong>
            with no version lets every release through with no cooldown, advisory, or retirement checks. Add a version requirement to limit it. Each package can be listed once.
          </span>
        </div>

        <div data-override-rows class="space-y-2">
          <%= inputs_for @form, :overrides, fn of -> %>
            <.override_row
              action_name={Form.input_name(of, :action)}
              action_value={Form.input_value(of, :action) || "allow"}
              package_name={Form.input_name(of, :package)}
              package_value={Form.input_value(of, :package)}
              requirement_name={Form.input_name(of, :requirement)}
              requirement_value={Form.input_value(of, :requirement)}
              id_name={Form.input_name(of, :id)}
              id_value={Form.input_value(of, :id)}
            />
          <% end %>
        </div>

        <div
          data-override-empty
          class={["text-sm text-grey-500 dark:text-grey-400 py-2", @overrides != [] && "hidden"]}
        >
          No overrides. Packages resolve through the restrictions above.
        </div>

        <template data-override-template>
          <.override_row
            action_name={@override_name <> "[__INDEX__][action]"}
            action_value="allow"
            package_name={@override_name <> "[__INDEX__][package]"}
            package_value={nil}
            requirement_name={@override_name <> "[__INDEX__][requirement]"}
            requirement_value={nil}
            id_name={nil}
            id_value={nil}
          />
        </template>

        <button
          type="button"
          data-override-add
          class="mt-4 inline-flex items-center gap-1 px-3 h-9 text-sm font-medium rounded border border-grey-200 dark:border-grey-700 bg-white dark:bg-grey-800 text-grey-700 dark:text-grey-200 hover:bg-grey-50 dark:hover:bg-grey-700 transition-colors cursor-pointer"
        >
          {icon(:heroicon, "plus", class: "w-4 h-4", width: 16, height: 16)} Add override
        </button>
      </div>
    </div>
    """
  end

  attr :action_name, :string, required: true
  attr :action_value, :string, required: true
  attr :package_name, :string, required: true
  attr :package_value, :any, required: true
  attr :requirement_name, :string, required: true
  attr :requirement_value, :any, required: true
  attr :id_name, :any, required: true
  attr :id_value, :any, required: true

  defp override_row(assigns) do
    assigns = assign(assigns, :tone_class, override_row_tone(assigns.action_value))

    ~H"""
    <div
      data-override-row
      class={[
        "relative grid grid-cols-1 gap-2 rounded-lg border bg-white dark:bg-grey-800 p-3 sm:flex sm:flex-wrap sm:items-center sm:p-2",
        "border-grey-200 dark:border-grey-700 border-l-4",
        @tone_class
      ]}
    >
      <input :if={@id_name} type="hidden" name={@id_name} value={@id_value} />

      <div
        data-decision
        class="inline-flex w-max max-w-[calc(100%-2.5rem)] sm:max-w-full rounded-md border border-grey-200 dark:border-grey-700 overflow-hidden"
      >
        <input type="hidden" data-decision-input name={@action_name} value={@action_value} />
        <.decision_button value="allow" label="Allow" active?={@action_value == "allow"} />
        <.decision_button value="deny" label="Deny" active?={@action_value == "deny"} />
      </div>

      <div class="relative min-w-0 sm:flex-1 sm:min-w-[10rem]">
        <input
          type="text"
          data-override-package
          name={@package_name}
          value={@package_value}
          placeholder="package name"
          autocomplete="off"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded="false"
          class="w-full px-3 py-2 border rounded text-sm font-mono bg-white dark:bg-grey-800 text-grey-900 dark:text-grey-100 border-grey-200 dark:border-grey-600 focus:outline-none focus:ring-1 focus:border-primary-600 focus:ring-primary-600"
        />
        <div
          data-override-suggestions="package"
          class="absolute inset-x-0 top-full z-50 mt-1 max-h-56 overflow-y-auto rounded-md border border-grey-200 dark:border-grey-600 bg-white dark:bg-grey-800 shadow-lg"
          hidden
        >
        </div>
      </div>
      <div class="relative min-w-0 sm:flex-1 sm:min-w-[10rem]">
        <input
          type="text"
          data-override-requirement
          name={@requirement_name}
          value={@requirement_value}
          placeholder="any version, or e.g. ~> 1.7"
          autocomplete="off"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded="false"
          class="w-full px-3 py-2 border rounded text-sm font-mono bg-white dark:bg-grey-800 text-grey-900 dark:text-grey-100 border-grey-200 dark:border-grey-600 focus:outline-none focus:ring-1 focus:border-primary-600 focus:ring-primary-600"
        />
        <div
          data-override-suggestions="version"
          class="absolute inset-x-0 top-full z-50 mt-1 max-h-56 overflow-y-auto rounded-md border border-grey-200 dark:border-grey-600 bg-white dark:bg-grey-800 shadow-lg"
          hidden
        >
        </div>
      </div>
      <button
        type="button"
        data-override-remove
        class="absolute right-2 top-2 sm:static size-9 flex items-center justify-center rounded text-grey-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/30 transition-colors cursor-pointer"
        aria-label="Remove override"
      >
        {icon(:heroicon, "trash", class: "w-4 h-4", width: 16, height: 16)}
      </button>
    </div>
    """
  end

  defp override_row_tone("deny"), do: "border-l-red-500"
  defp override_row_tone(_), do: "border-l-green-500"

  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :active?, :boolean, required: true

  defp decision_button(assigns) do
    ~H"""
    <button
      type="button"
      data-decision-value={@value}
      data-active={@active? && "true"}
      class={[
        "inline-flex items-center gap-1.5 px-2.5 sm:px-3 h-9 text-sm font-medium cursor-pointer transition-colors",
        "text-grey-600 dark:text-grey-300 bg-white dark:bg-grey-800 hover:bg-grey-50 dark:hover:bg-grey-700",
        @value == "allow" &&
          "data-[active=true]:bg-green-50 data-[active=true]:text-green-700 dark:data-[active=true]:bg-green-900/20 dark:data-[active=true]:text-green-300",
        @value == "deny" &&
          "data-[active=true]:bg-red-50 data-[active=true]:text-red-700 dark:data-[active=true]:bg-red-900/20 dark:data-[active=true]:text-red-300 border-l border-grey-200 dark:border-grey-700"
      ]}
    >
      <span class={[
        "size-1.5 rounded-full",
        @value == "allow" && "bg-green-600 dark:bg-green-300",
        @value == "deny" && "bg-red-600 dark:bg-red-300"
      ]}>
      </span>
      {@label}
    </button>
    """
  end

  attr :class, :string, default: ""
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :variant, :string, default: "neutral", values: ~w(neutral danger)
  attr :rest, :global, include: ~w(phx-click phx-hook data-target)

  defp header_action(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "inline-flex items-center gap-1 px-3 h-9 text-sm font-medium rounded border transition-colors cursor-pointer",
        header_action_classes(@variant),
        @class
      ]}
      {@rest}
    >
      {icon(:heroicon, @icon, class: "w-4 h-4", width: 16, height: 16)} {@label}
    </button>
    """
  end

  defp header_action_classes("danger"),
    do:
      "border-transparent text-red-600 dark:text-red-300 hover:bg-red-50 dark:hover:bg-red-900/30"

  defp header_action_classes(_),
    do:
      "border-grey-200 dark:border-grey-700 text-grey-700 dark:text-grey-200 hover:bg-grey-50 dark:hover:bg-grey-700"

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :icon_color, :string, default: "text-grey-500"
  attr :description, :string, required: true
  attr :disabled_text, :string, default: nil
  attr :enabled?, :boolean, default: false
  slot :inner_block, required: true

  defp rule_block(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="RuleToggle"
      class="grid grid-cols-[1.25rem_1fr] md:grid-cols-[8rem_1fr] gap-x-3 gap-y-2 py-3"
    >
      <label class="group/rule contents cursor-pointer md:flex md:items-center md:gap-3 md:min-h-9">
        <input type="checkbox" checked={@enabled?} class="sr-only peer" data-rule-enabled />
        <span class="self-center w-4 h-4 rounded border-[1.5px] flex items-center justify-center flex-shrink-0 transition-colors bg-white dark:bg-grey-800 border-grey-300 dark:border-grey-600 peer-checked:bg-blue-600 peer-checked:border-blue-600">
          <span class="hidden group-has-[:checked]/rule:flex text-white">
            {icon(:heroicon, "check", class: "w-3 h-3", width: 12, height: 12)}
          </span>
        </span>
        <span class="min-h-9 flex items-center text-sm font-semibold text-grey-900 dark:text-white">
          {@title}
        </span>
      </label>
      <div
        data-rule-body
        class={["col-start-2 md:col-start-auto min-h-9 flex items-center", !@enabled? && "hidden"]}
      >
        {render_slot(@inner_block)}
      </div>
      <div
        :if={@disabled_text}
        data-rule-disabled
        class={[
          "col-start-2 md:col-start-auto min-h-9 items-center text-sm italic text-grey-500 dark:text-grey-300",
          @enabled? && "hidden",
          !@enabled? && "flex"
        ]}
      >
        {@disabled_text}
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :active?, :boolean, default: false

  defp retirement_checkbox(assigns) do
    ~H"""
    <label class="group/card inline-flex items-center gap-2 rounded-md border border-grey-200 dark:border-grey-700 bg-white dark:bg-grey-800 px-3 h-9 text-sm font-medium text-grey-700 dark:text-grey-200 cursor-pointer transition-colors hover:border-grey-300 dark:hover:border-grey-600 has-[:checked]:border-red-300 dark:has-[:checked]:border-red-700 has-[:checked]:bg-red-50 dark:has-[:checked]:bg-red-900/20">
      <input type="checkbox" name={@name} value={@value} checked={@active?} class="sr-only" />
      <span class="w-4 h-4 rounded border-[1.5px] flex items-center justify-center flex-shrink-0 transition-colors bg-white dark:bg-grey-800 border-grey-300 dark:border-grey-600 group-has-[:checked]/card:bg-red-600 group-has-[:checked]/card:border-red-600">
        <span class="hidden group-has-[:checked]/card:flex text-white">
          {icon(:heroicon, "check", class: "w-3 h-3", width: 12, height: 12)}
        </span>
      </span>
      {@label}
    </label>
    """
  end

  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :policy, :map, required: true

  defp delete_policy_modal(assigns) do
    ~H"""
    <.modal id="delete-policy-modal" title="Delete policy">
      <p class="text-sm text-grey-600 dark:text-grey-300 mb-4">
        Are you sure you want to delete <strong class="text-grey-900 dark:text-white">{@policy.name}</strong>?
        This cannot be undone.
      </p>
      <p class="text-sm text-grey-600 dark:text-grey-300 mb-6">
        Please type <strong class="text-grey-900 dark:text-white">{@policy.name}</strong> to confirm.
      </p>
      <.sudo_form
        current_user={@current_user}
        action={~p"/dashboard/orgs/#{@organization}/policies/#{@policy.name}"}
        method="delete"
        id="delete-policy-form"
      >
        <.text_input
          id="delete-policy-name-input"
          name="policy_name"
          placeholder={@policy.name}
          required
          pattern={@policy.name}
          title={"Please type '#{@policy.name}' to confirm"}
        />
      </.sudo_form>
      <:footer>
        <.button type="button" variant="secondary" phx-click={hide_modal("delete-policy-modal")}>
          Cancel
        </.button>
        <.button type="submit" form="delete-policy-form" variant="danger">
          Delete policy
        </.button>
      </:footer>
    </.modal>
    """
  end

  # The index of a repository tab within the embeds list, read from the
  # generated field name (e.g. "policy[repositories][0][...]").
  defp repo_index(form) do
    case Regex.run(~r/\[repositories\]\[(\d+)\]/, Form.input_name(form, :repository)) do
      [_, index] -> String.to_integer(index)
      _ -> 0
    end
  end

  # The hidden fields that keep a repository tab matched and named on submit.
  defp repo_hidden_fields(form) do
    [
      {Form.input_name(form, :id), Form.input_value(form, :id)},
      {Form.input_name(form, :repository), Form.input_value(form, :repository)}
    ]
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
  end

  defp repo_label(%Ecto.Changeset{} = changeset),
    do: Ecto.Changeset.get_field(changeset, :repository)

  defp repo_label(%{repository: repository}), do: repository
  defp repo_label(%{"repository" => repository}), do: repository

  defp repo_summary(repo) do
    parts =
      restriction_summary_items(repo) ++
        override_summary_items(repo)

    case parts do
      [] ->
        "no restrictions"

      parts ->
        parts
        |> Enum.map(fn {_tone, label} -> label end)
        |> Enum.join(", ")
    end
  end

  defp restriction_summary_items(repo) do
    []
    |> maybe_summary(repo_field(repo, :cooldown), fn cooldown ->
      {"blue", cooldown}
    end)
    |> maybe_summary(repo_field(repo, :advisory_min_severity), fn severity ->
      {"yellow", ">= #{severity_word(severity)}"}
    end)
    |> maybe_summary(present_list(repo_field(repo, :retirement_reasons)), fn reasons ->
      {"red", "#{length(reasons)} retirement"}
    end)
    |> Enum.reverse()
  end

  defp override_summary_items(repo) do
    case repo_field(repo, :overrides) || [] do
      [] ->
        []

      overrides ->
        [{"grey", "#{length(overrides)} #{ngettext("override", "overrides", length(overrides))}"}]
    end
  end

  defp maybe_summary(items, nil, _fun), do: items
  defp maybe_summary(items, "", _fun), do: items
  defp maybe_summary(items, value, fun), do: [fun.(value) | items]

  defp repo_field(%Form{} = form, field), do: Form.input_value(form, field)

  defp repo_field(%Ecto.Changeset{} = changeset, field),
    do: Ecto.Changeset.get_field(changeset, field)

  defp repo_field(map, field) when is_map(map),
    do: Map.get(map, field) || Map.get(map, Atom.to_string(field))

  defp present_list([]), do: nil
  defp present_list(nil), do: nil
  defp present_list(list) when is_list(list), do: list

  defp ngettext(singular, _plural, 1), do: singular
  defp ngettext(_singular, plural, _count), do: plural

  defp repo_meta("hexpm"),
    do: %{label: "hexpm", kind: :public, desc: "Public packages from the hex.pm registry"}

  defp repo_meta(name),
    do: %{label: name, kind: :org, desc: "Your organization's own packages"}

  defp repo_icon(:public), do: "globe-alt"
  defp repo_icon(:org), do: "building-office"

  defp repo_kind_label(:public), do: "public"
  defp repo_kind_label(:org), do: "your repo"

  defp severity_select_options do
    for value <- 1..4 do
      name = Enum.at(OrganizationPolicy.severity_names(), value)
      {">= #{String.capitalize(name)}", value}
    end
  end

  defp severity_dot_class(value) do
    case Integer.parse(to_string(value || "")) do
      {1, ""} -> "bg-blue-500"
      {2, ""} -> "bg-yellow-500"
      {3, ""} -> "bg-red-500"
      {4, ""} -> "bg-red-600"
      _ -> "bg-grey-300 dark:bg-grey-500"
    end
  end

  defp severity_word(value) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> Enum.at(OrganizationPolicy.severity_names(), int, "")
      _ -> ""
    end
  end

  @retirement_subtitles %{
    "security" => "Pulled because of a security issue",
    "invalid" => "Broken or unbuildable release",
    "deprecated" => "Marked end-of-life by the author",
    "renamed" => "Republished under a new package name",
    "other" => "Author-specified reason"
  }

  defp retirement_reason_options do
    order = ["security", "invalid", "deprecated", "renamed", "other"]
    reasons = OrganizationPolicy.retirement_reasons()
    by_name = Map.new(reasons, fn {value, name} -> {name, value} end)

    Enum.map(order, fn name ->
      {String.capitalize(name), Map.fetch!(by_name, name),
       Map.fetch!(@retirement_subtitles, name)}
    end)
  end

  defp selected_retirement_reasons(form) do
    case Form.input_value(form, :retirement_reasons) do
      nil -> []
      list when is_list(list) -> Enum.map(list, &normalize_reason/1)
      _ -> []
    end
  end

  defp normalize_reason(value) when is_integer(value), do: value

  defp normalize_reason(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> value
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp visibility_value(form, policy) do
    case Form.input_value(form, :visibility) do
      nil -> policy.visibility
      "" -> policy.visibility
      value -> value
    end
  end

  defp visibility_description("private"), do: "Only organization members can fetch this policy"
  defp visibility_description(_), do: "Visible to anyone with read access to the org"
end
