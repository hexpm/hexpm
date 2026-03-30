defmodule HexpmWeb.Components.Input do
  @moduledoc """
  Reusable form input components with label and error support.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import HexpmWeb.ViewIcons, only: [icon: 3]

  @doc """
  Renders a text input field with optional label and errors.

  ## Examples

      <.text_input id="username" name="username" />
      <.text_input id="email" name="email" type="email" label="Email Address" />
      <.text_input id="username" name="username" label="Username" required errors={["can't be blank"]} />
      <.text_input field={@form[:email]} label="Email" />
  """
  attr :class, :string, default: ""
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :id, :string, default: nil
  attr :label, :string, default: nil
  attr :label_class, :string, default: ""
  attr :name, :string, default: nil
  attr :placeholder, :string, default: ""
  attr :required, :boolean, default: false

  attr :show_errors, :boolean,
    default: nil,
    doc:
      "Controls error display: nil (default - show all), true (always show), false (never show)"

  attr :list, :string,
    default: nil,
    doc: "ID of a <datalist> element for autocomplete suggestions"

  attr :type, :string, default: "text"
  attr :value, :string, default: nil

  attr :rest, :global,
    include: ~w(pattern title),
    doc: "Additional HTML attributes to pass to the input element"

  def text_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    # For controller views, always show errors after submission
    # For LiveView, you can control with show_errors attribute
    errors =
      case assigns[:show_errors] do
        false -> []
        _ -> field.errors
      end

    assigns
    |> assign(:field, nil)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign(:id, field.id)
    |> assign(:name, field.name)
    |> assign(:value, field.value)
    |> text_input()
  end

  def text_input(assigns) do
    ~H"""
    <div class="relative">
      <.label :if={@label} for={@id} label={@label} required={@required} class={@label_class} />
      <input
        id={@id}
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        list={@list}
        class={[
          "w-full h-12 bg-white border rounded px-3",
          "text-grey-900 placeholder:text-grey-300",
          "focus:outline-none focus:ring-1",
          @errors != [] && "border-red-300 focus:border-red-600 focus:ring-red-600",
          @errors == [] && "border-grey-200 focus:border-primary-600 focus:ring-primary-600",
          @class
        ]}
        {@rest}
      />
      <.errors errors={@errors} />
    </div>
    """
  end

  @doc """
  Renders a select dropdown with optional label and errors.

  ## Examples

      <.select_input id="sort" name="sort" options={[{"Name", "name"}, {"Date", "date"}]} />
      <.select_input id="status" name="status" label="Status" options={@status_options} />
      <.select_input field={@form[:category]} label="Category" options={@categories} />
      <.select_input
        id="country"
        name="country"
        label="Country"
        options={[{"United States", "us"}, {"Canada", "ca"}]}
        required
        errors={["can't be blank"]}
      />
  """
  attr :class, :string, default: ""
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :id, :string, default: nil
  attr :label, :string, default: nil
  attr :label_class, :string, default: ""
  attr :name, :string, default: nil
  attr :options, :list, required: true, doc: "List of {label, value} tuples for select options"
  attr :prompt, :string, default: nil, doc: "Optional prompt text for the first option"
  attr :required, :boolean, default: false
  attr :rest, :global, include: ~w(disabled multiple onchange)

  attr :show_errors, :boolean,
    default: nil,
    doc:
      "Controls error display: nil (default - show all), true (always show), false (never show)"

  attr :variant, :string,
    default: "default",
    values: ["default", "light"],
    doc: "Style variant: 'default' uses grey-300 border, 'light' uses grey-200 border"

  attr :value, :any, default: nil

  def select_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors =
      case assigns[:show_errors] do
        false -> []
        _ -> field.errors
      end

    # Use field value if present, otherwise fall back to explicit value attribute
    value = field.value || assigns[:value]

    assigns
    |> assign(:field, nil)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign(:id, field.id)
    |> assign(:name, field.name)
    |> assign(:value, value)
    |> assign_new(:variant, fn -> "default" end)
    |> select_input()
  end

  def select_input(assigns) do
    assigns = assign_new(assigns, :variant, fn -> "default" end)

    ~H"""
    <div>
      <.label :if={@label} for={@id} label={@label} required={@required} class={@label_class} />
      <div class="relative">
        <select
          id={@id}
          name={@name}
          class={[
            "w-full h-12 pl-4 pr-10 bg-white border rounded-lg",
            "text-grey-900 font-medium cursor-pointer",
            "focus:outline-none focus:ring-2",
            "appearance-none",
            select_border_classes(@variant, @errors),
            @class
          ]}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          <%= for {label, value} <- @options do %>
            <option value={value} selected={to_string(@value) == to_string(value)}>
              {label}
            </option>
          <% end %>
        </select>
        <%!-- Chevron down icon --%>
        <div class="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-grey-400">
          {icon(:heroicon, "chevron-down", width: 15, height: 15)}
        </div>
      </div>
      <.errors errors={@errors} />
    </div>
    """
  end

  @doc """
  Renders a password input with visibility toggle, optional label and errors.

  ## Examples

      <.password_input id="password" name="password" />
      <.password_input id="password" name="password" label="Password" required />
      <.password_input id="password" name="password" label="Password" errors={["is too short"]} />

      <.password_input id="password" name="password" label="Password">
        <:hint>
          <a href="/forgot">Forgot Password?</a>
        </:hint>
      </.password_input>
  """
  attr :class, :string, default: ""
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :id, :string, default: nil
  attr :label, :string, default: nil
  attr :label_class, :string, default: ""
  attr :name, :string, default: nil
  attr :placeholder, :string, default: ""
  attr :required, :boolean, default: false

  attr :show_errors, :boolean,
    default: nil,
    doc:
      "Controls error display: nil (default - show all), true (always show), false (never show)"

  attr :show_strength, :boolean,
    default: false,
    doc: "Show password strength meter and requirements"

  attr :match_password_id, :string,
    default: nil,
    doc: "ID of the password field to match against (for confirmation fields)"

  slot :hint,
    doc: "Additional content displayed next to the label (e.g., 'Forgot Password?' link)"

  def password_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    # For controller views, always show errors after submission
    # For LiveView, you can control with show_errors attribute
    errors =
      case assigns[:show_errors] do
        false -> []
        _ -> field.errors
      end

    # If using dynamic password matching, filter out confirmation errors
    # since the hook handles them
    errors =
      if assigns[:match_password_id] do
        Enum.reject(errors, fn
          {"does not match password", _} -> true
          {"does not match confirmation", _} -> true
          "does not match password" -> true
          "does not match confirmation" -> true
          _ -> false
        end)
      else
        errors
      end

    assigns
    |> assign(:field, nil)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign(:id, field.id)
    |> assign(:name, field.name)
    |> password_input()
  end

  def password_input(assigns) do
    assigns =
      assigns
      |> assign_new(:show_strength, fn -> false end)
      |> assign_new(:match_password_id, fn -> nil end)

    ~H"""
    <div
      class="relative"
      phx-hook={password_hook(@show_strength, @match_password_id)}
      id={password_container_id(@id, @show_strength, @match_password_id)}
      data-password-id={@match_password_id && "##{@match_password_id}"}
    >
      <div
        :if={@label || @hint != []}
        class="flex items-center justify-between mb-[6px]"
      >
        <.label
          :if={@label}
          for={@id}
          label={@label}
          required={@required}
          no_margin
          class={@label_class}
        />
        {render_slot(@hint)}
      </div>
      <div class="relative">
        <input
          id={@id}
          type="password"
          name={@name}
          placeholder={@placeholder}
          class={[
            "w-full h-12 bg-white border rounded px-3 pr-10",
            "text-grey-900 placeholder:text-grey-300",
            "focus:outline-none focus:ring-1",
            @errors != [] && "border-red-300 focus:border-red-600 focus:ring-red-600",
            @errors == [] &&
              "border-grey-200 focus:border-primary-600 focus:ring-primary-600",
            @class
          ]}
        />
        <button
          type="button"
          tabindex="-1"
          class="absolute right-3 top-1/2 -translate-y-1/2 text-grey-400 hover:text-grey-600 transition-colors"
          phx-click={toggle_password_visibility(@id)}
          aria-label="Toggle password visibility"
        >
          <span id={"#{@id}-eye-icon"}>
            {icon(:heroicon, "eye", width: 16, height: 16)}
          </span>
          <span id={"#{@id}-eye-slash-icon"} class="hidden">
            {icon(:heroicon, "eye-slash", width: 16, height: 16)}
          </span>
        </button>
      </div>

      <%!-- Password Strength Meter --%>
      <div :if={@show_strength} class="mt-3">
        <%!-- Strength Bar --%>
        <div class="flex items-center gap-3 mb-3">
          <div
            class="flex-1 h-2 bg-grey-100 rounded-full overflow-hidden"
            role="progressbar"
            aria-valuemin="0"
            aria-valuemax="100"
            aria-valuenow="0"
            aria-label="Password strength"
          >
            <div
              data-strength-bar
              class="h-full w-0 rounded-full transition-all duration-300"
            >
            </div>
          </div>
          <span
            data-strength-label
            class="text-small font-medium min-w-[60px]"
            aria-live="polite"
          >
          </span>
        </div>

        <%!-- Requirements Checklist --%>
        <div class="space-y-2" aria-live="polite" aria-label="Password requirements">
          <.password_requirement key="length" label="At least 8 characters" />
          <.password_requirement key="lowercase" label="One lowercase letter" />
          <.password_requirement key="uppercase" label="One uppercase letter" />
          <.password_requirement key="number" label="One number" />
        </div>
      </div>

      <%!-- Dynamic Password Match Error --%>
      <div
        :if={@match_password_id}
        data-match-error
        class="mt-1 hidden"
        role="alert"
        aria-live="polite"
      >
        <p class="flex items-center gap-1 text-small text-red-600">
          {icon(:heroicon, "exclamation-circle", width: 16, height: 16)}
          <span>Passwords do not match</span>
        </p>
      </div>

      <.errors errors={@errors} />
    </div>
    """
  end

  @doc """
  Renders a label for an input field.
  """
  attr :class, :string, default: ""
  attr :for, :string, required: true
  attr :label, :string, required: true
  attr :no_margin, :boolean, default: false, doc: "Remove bottom margin (useful in flex layouts)"
  attr :required, :boolean, default: false

  def label(assigns) do
    ~H"""
    <label
      for={@for}
      class={[
        "block text-small font-medium text-grey-900",
        !@no_margin && "mb-[6px]",
        @class
      ]}
    >
      {@label}
      <span :if={@required} class="text-red-600 ml-1">*</span>
    </label>
    """
  end

  @doc """
  Renders error messages for an input field.
  """
  attr :errors, :list, default: []

  def errors(assigns) do
    ~H"""
    <div :if={@errors != []} class="mt-1">
      <p :for={msg <- @errors} class="flex items-center gap-1 text-small text-red-600">
        {icon(:heroicon, "exclamation-circle", width: 16, height: 16)}
        <span>{msg}</span>
      </p>
    </div>
    """
  end

  # Renders a single password requirement item with check/x icons.
  # Private component used by password_input for the requirements checklist.
  attr :key, :string, required: true
  attr :label, :string, required: true

  defp password_requirement(assigns) do
    ~H"""
    <div
      data-requirement={@key}
      class="flex items-center gap-2 text-small text-grey-600"
    >
      <span class="relative w-4 h-4">
        <span data-x-icon class="absolute inset-0">
          {icon(:heroicon, "x-circle", class: "w-4 h-4 text-red-500")}
        </span>
        <span data-check-icon class="absolute inset-0 hidden">
          {icon(:heroicon, "check-circle", class: "w-4 h-4 transition-colors")}
        </span>
      </span>
      <span>{@label}</span>
    </div>
    """
  end

  # Determines which Phoenix hook to use for the password input
  defp password_hook(show_strength, match_password_id) do
    cond do
      show_strength -> "PasswordStrength"
      match_password_id -> "PasswordMatch"
      true -> nil
    end
  end

  # Generates the container ID for password input hooks
  defp password_container_id(input_id, show_strength, match_password_id) do
    cond do
      show_strength -> "#{input_id}-strength-container"
      match_password_id -> "#{input_id}-match-container"
      true -> nil
    end
  end

  defp toggle_password_visibility(input_id) do
    JS.toggle_attribute({"type", "text", "password"}, to: "##{input_id}")
    |> JS.toggle_class("hidden", to: "##{input_id}-eye-icon")
    |> JS.toggle_class("hidden", to: "##{input_id}-eye-slash-icon")
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error(msg) when is_binary(msg), do: msg

  # Helper function to determine border classes based on variant and error state
  defp select_border_classes("light", errors) when errors != [] do
    "border-red-300 focus:border-red-600 focus:ring-red-600 focus:ring-opacity-20"
  end

  defp select_border_classes("light", _errors) do
    "border-grey-200 focus:border-purple-600 focus:ring-purple-600 focus:ring-opacity-20"
  end

  defp select_border_classes("default", errors) when errors != [] do
    "border-red-300 focus:border-red-600 focus:ring-red-600 focus:ring-opacity-20"
  end

  defp select_border_classes("default", _errors) do
    "border-grey-300 focus:border-primary-600 focus:ring-primary-600 focus:ring-opacity-20"
  end
end
