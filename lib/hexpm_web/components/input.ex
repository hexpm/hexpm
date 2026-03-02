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

  attr :type, :string, default: "text"
  attr :value, :string, default: nil
  attr :rest, :global, doc: "Additional HTML attributes to pass to the input element"

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
    <div class="tw:relative">
      <.label :if={@label} for={@id} label={@label} required={@required} class={@label_class} />
      <input
        id={@id}
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        class={[
          "tw:w-full tw:h-12 tw:bg-white tw:border tw:rounded tw:px-3",
          "tw:text-grey-900 tw:placeholder:text-grey-300",
          "tw:focus:outline-none tw:focus:ring-1",
          @errors != [] && "tw:border-red-300 tw:focus:border-red-600 tw:focus:ring-red-600",
          @errors == [] && "tw:border-grey-200 tw:focus:border-primary-600 tw:focus:ring-primary-600",
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
  attr :rest, :global, include: ~w(disabled multiple)

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
      <div class="tw:relative">
        <select
          id={@id}
          name={@name}
          class={[
            "tw:w-full tw:h-12 tw:pl-4 tw:pr-10 tw:bg-white tw:border tw:rounded-lg",
            "tw:text-grey-900 tw:font-medium tw:cursor-pointer",
            "tw:focus:outline-none tw:focus:ring-2",
            "tw:appearance-none",
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
        <div class="tw:absolute tw:right-3 tw:top-1/2 tw:-translate-y-1/2 tw:pointer-events-none tw:text-grey-400">
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
      class="tw:relative"
      phx-hook={password_hook(@show_strength, @match_password_id)}
      id={password_container_id(@id, @show_strength, @match_password_id)}
      data-password-id={@match_password_id && "##{@match_password_id}"}
    >
      <div
        :if={@label || @hint != []}
        class="tw:flex tw:items-center tw:justify-between tw:mb-[6px]"
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
      <div class="tw:relative">
        <input
          id={@id}
          type="password"
          name={@name}
          placeholder={@placeholder}
          class={[
            "tw:w-full tw:h-12 tw:bg-white tw:border tw:rounded tw:px-3 tw:pr-10",
            "tw:text-grey-900 tw:placeholder:text-grey-300",
            "tw:focus:outline-none tw:focus:ring-1",
            @errors != [] && "tw:border-red-300 tw:focus:border-red-600 tw:focus:ring-red-600",
            @errors == [] &&
              "tw:border-grey-200 tw:focus:border-primary-600 tw:focus:ring-primary-600",
            @class
          ]}
        />
        <button
          type="button"
          tabindex="-1"
          class="tw:absolute tw:right-3 tw:top-1/2 tw:-translate-y-1/2 tw:text-grey-400 tw:hover:text-grey-600 tw:transition-colors"
          phx-click={toggle_password_visibility(@id)}
          aria-label="Toggle password visibility"
        >
          <span id={"#{@id}-eye-icon"}>
            {icon(:heroicon, "eye", width: 16, height: 16)}
          </span>
          <span id={"#{@id}-eye-slash-icon"} class="tw:hidden">
            {icon(:heroicon, "eye-slash", width: 16, height: 16)}
          </span>
        </button>
      </div>

      <%!-- Password Strength Meter --%>
      <div :if={@show_strength} class="tw:mt-3">
        <%!-- Strength Bar --%>
        <div class="tw:flex tw:items-center tw:gap-3 tw:mb-3">
          <div
            class="tw:flex-1 tw:h-2 tw:bg-grey-100 tw:rounded-full tw:overflow-hidden"
            role="progressbar"
            aria-valuemin="0"
            aria-valuemax="100"
            aria-valuenow="0"
            aria-label="Password strength"
          >
            <div
              data-strength-bar
              class="tw:h-full tw:rounded-full tw:transition-all tw:duration-300"
              style="width: 0%"
            >
            </div>
          </div>
          <span
            data-strength-label
            class="tw:text-small tw:font-medium tw:min-w-[60px]"
            aria-live="polite"
          >
          </span>
        </div>

        <%!-- Requirements Checklist --%>
        <div class="tw:space-y-2" aria-live="polite" aria-label="Password requirements">
          <.password_requirement key="length" label="At least 7 characters" />
          <.password_requirement key="lowercase" label="One lowercase letter" />
          <.password_requirement key="uppercase" label="One uppercase letter" />
          <.password_requirement key="number" label="One number" />
          <.password_requirement key="special" label="One special character" />
        </div>
      </div>

      <%!-- Dynamic Password Match Error --%>
      <div
        :if={@match_password_id}
        data-match-error
        class="tw:mt-1 tw:hidden"
        role="alert"
        aria-live="polite"
      >
        <p class="tw:flex tw:items-center tw:gap-1 tw:text-small tw:text-red-600">
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
        "tw:block tw:text-small tw:font-medium tw:text-grey-900",
        !@no_margin && "tw:mb-[6px]",
        @class
      ]}
    >
      {@label}
      <span :if={@required} class="tw:text-red-600 tw:ml-1">*</span>
    </label>
    """
  end

  @doc """
  Renders error messages for an input field.
  """
  attr :errors, :list, default: []

  def errors(assigns) do
    ~H"""
    <div :if={@errors != []} class="tw:mt-1">
      <p :for={msg <- @errors} class="tw:flex tw:items-center tw:gap-1 tw:text-small tw:text-red-600">
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
      class="tw:flex tw:items-center tw:gap-2 tw:text-small tw:text-grey-600"
    >
      <span class="tw:relative tw:w-4 tw:h-4">
        <span data-x-icon class="tw:absolute tw:inset-0">
          {icon(:heroicon, "x-circle", class: "tw:w-4 tw:h-4 tw:text-red-500")}
        </span>
        <span data-check-icon class="tw:absolute tw:inset-0 tw:hidden">
          {icon(:heroicon, "check-circle", class: "tw:w-4 tw:h-4 tw:transition-colors")}
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
    |> JS.toggle_class("tw:hidden", to: "##{input_id}-eye-icon")
    |> JS.toggle_class("tw:hidden", to: "##{input_id}-eye-slash-icon")
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error(msg) when is_binary(msg), do: msg

  # Helper function to determine border classes based on variant and error state
  defp select_border_classes("light", errors) when errors != [] do
    "tw:border-red-300 tw:focus:border-red-600 tw:focus:ring-red-600 tw:focus:ring-opacity-20"
  end

  defp select_border_classes("light", _errors) do
    "tw:border-grey-200 tw:focus:border-purple-600 tw:focus:ring-purple-600 tw:focus:ring-opacity-20"
  end

  defp select_border_classes("default", errors) when errors != [] do
    "tw:border-red-300 tw:focus:border-red-600 tw:focus:ring-red-600 tw:focus:ring-opacity-20"
  end

  defp select_border_classes("default", _errors) do
    "tw:border-grey-300 tw:focus:border-primary-600 tw:focus:ring-primary-600 tw:focus:ring-opacity-20"
  end
end
