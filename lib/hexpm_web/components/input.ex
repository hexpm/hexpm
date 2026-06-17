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
    include: ~w(min max pattern title),
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
    |> assign(:value, assigns[:value] || field.value)
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
          "w-full h-12 bg-white border rounded px-3 dark:bg-grey-800",
          "text-grey-900 placeholder:text-grey-300 dark:text-grey-100 dark:placeholder:text-grey-400",
          "focus:outline-none focus:ring-1",
          @errors != [] &&
            "border-red-300 focus:border-red-600 focus:ring-red-600 dark:border-red-700 dark:focus:border-red-400 dark:focus:ring-red-400",
          @errors == [] &&
            "border-grey-200 focus:border-primary-600 focus:ring-primary-600 dark:border-grey-600 dark:focus:border-primary-400 dark:focus:ring-primary-400",
          @class
        ]}
        {@rest}
      />
      <.errors errors={@errors} />
    </div>
    """
  end

  @doc """
  Renders a textarea field with optional label and errors.

  ## Examples

      <.textarea_input id="bio" name="bio" />
      <.textarea_input field={@form[:description]} label="Description" rows="3" />
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
  attr :rows, :string, default: "3"
  attr :value, :string, default: nil

  attr :show_errors, :boolean,
    default: nil,
    doc:
      "Controls error display: nil (default - show all), true (always show), false (never show)"

  attr :rest, :global, doc: "Additional HTML attributes to pass to the textarea element"

  def textarea_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
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
    |> assign(:value, assigns[:value] || field.value)
    |> textarea_input()
  end

  def textarea_input(assigns) do
    ~H"""
    <div>
      <.label :if={@label} for={@id} label={@label} required={@required} class={@label_class} />
      <textarea
        id={@id}
        name={@name}
        rows={@rows}
        placeholder={@placeholder}
        class={[
          "w-full px-3 py-2.5 border rounded text-sm",
          "bg-white dark:bg-grey-800 text-grey-900 dark:text-grey-100",
          "placeholder:text-grey-300 dark:placeholder:text-grey-400",
          "focus:outline-none focus:ring-1",
          @errors != [] &&
            "border-red-300 focus:border-red-600 focus:ring-red-600 dark:border-red-700",
          @errors == [] &&
            "border-grey-200 focus:border-primary-600 focus:ring-primary-600 dark:border-grey-600",
          @class
        ]}
        {@rest}
      ><%= @value %></textarea>
      <.errors errors={@errors} />
    </div>
    """
  end

  @doc """
  Renders an accessible toggle switch backed by a hidden checkbox.

  The label and helper text live in the calling template; this component
  only renders the switch itself.

  ## Examples

      <.toggle_switch name="settings[notify]" value="1" checked={@notify?} />
  """
  attr :checked, :boolean, default: false
  attr :class, :string, default: ""
  attr :disabled, :boolean, default: false
  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :hidden_value, :string, default: nil, doc: "Hidden input value submitted when unchecked"
  attr :value, :string, default: "1"
  attr :rest, :global

  def toggle_switch(assigns) do
    ~H"""
    <label class={[
      "relative inline-flex items-center flex-shrink-0",
      if(@disabled, do: "cursor-not-allowed opacity-50", else: "cursor-pointer"),
      @class
    ]}>
      <input :if={@hidden_value && @name} type="hidden" name={@name} value={@hidden_value} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        disabled={@disabled}
        class="sr-only peer"
        {@rest}
      />
      <span class="w-11 h-6 bg-grey-200 dark:bg-grey-700 rounded-full peer-checked:bg-primary-600 peer-focus-visible:ring-2 peer-focus-visible:ring-primary-500 peer-focus-visible:ring-offset-2 transition-colors">
      </span>
      <span class="absolute left-0.5 top-0.5 w-5 h-5 bg-white dark:bg-grey-100 rounded-full shadow transition-transform pointer-events-none peer-checked:translate-x-5">
      </span>
    </label>
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
  attr :rest, :global, include: ~w(disabled multiple phx-hook)

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
            "w-full h-12 pl-4 pr-10 bg-white border rounded-lg dark:bg-grey-800",
            "text-grey-900 font-medium cursor-pointer dark:text-grey-100",
            "focus:outline-none focus:ring-2 dark:focus:ring-offset-grey-800",
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
        <div class="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-grey-400 dark:text-grey-300">
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
            "text-grey-900 placeholder:text-grey-300 dark:bg-grey-800 dark:text-grey-100 dark:placeholder:text-grey-400",
            "focus:outline-none focus:ring-1",
            @errors != [] &&
              "border-red-300 focus:border-red-600 focus:ring-red-600 dark:border-red-700 dark:focus:border-red-400 dark:focus:ring-red-400",
            @errors == [] &&
              "border-grey-200 focus:border-primary-600 focus:ring-primary-600 dark:border-grey-600 dark:focus:border-primary-400 dark:focus:ring-primary-400",
            @class
          ]}
        />
        <button
          type="button"
          tabindex="-1"
          class="absolute right-3 top-1/2 -translate-y-1/2 text-grey-400 hover:text-grey-600 transition-colors dark:text-grey-300 dark:hover:text-grey-100"
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
            class="text-small font-medium min-w-[60px] dark:text-grey-200"
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
        <p class="flex items-center gap-1 text-small text-red-600 dark:text-red-400">
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
        "block text-small font-medium text-grey-900 dark:text-grey-100",
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
      <p
        :for={msg <- @errors}
        class="flex items-center gap-1 text-small text-red-600 dark:text-red-400"
      >
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
      class="flex items-center gap-2 text-small text-grey-600 dark:text-grey-300"
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

  @doc """
  Translates a changeset error tuple `{msg, opts}` into a flat string,
  interpolating `%{key}` placeholders from `opts`.
  """
  def translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  def translate_error(msg) when is_binary(msg), do: msg

  @doc """
  Returns the translated errors associated with `field` on the given
  form. Returns `[]` when the form is not backed by a changeset.
  """
  def field_errors(form, field) do
    case form.source do
      %Ecto.Changeset{} = changeset ->
        changeset.errors
        |> Keyword.get_values(field)
        |> Enum.map(&translate_error/1)

      _ ->
        []
    end
  end

  # Helper function to determine border classes based on variant and error state
  defp select_border_classes("light", errors) when errors != [] do
    "border-red-300 focus:border-red-600 focus:ring-red-600 focus:ring-opacity-20 dark:border-red-700 dark:focus:border-red-400 dark:focus:ring-red-400"
  end

  defp select_border_classes("light", _errors) do
    "border-grey-200 focus:border-purple-600 focus:ring-purple-600 focus:ring-opacity-20 dark:border-grey-600 dark:focus:border-primary-400 dark:focus:ring-primary-400"
  end

  defp select_border_classes("default", errors) when errors != [] do
    "border-red-300 focus:border-red-600 focus:ring-red-600 focus:ring-opacity-20 dark:border-red-700 dark:focus:border-red-400 dark:focus:ring-red-400"
  end

  defp select_border_classes("default", _errors) do
    "border-grey-300 focus:border-primary-600 focus:ring-primary-600 focus:ring-opacity-20 dark:border-grey-600 dark:focus:border-primary-400 dark:focus:ring-primary-400"
  end
end
