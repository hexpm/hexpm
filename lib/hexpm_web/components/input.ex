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
      />
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

    assigns
    |> assign(:field, nil)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign(:id, field.id)
    |> assign(:name, field.name)
    |> password_input()
  end

  def password_input(assigns) do
    ~H"""
    <div class="tw:relative">
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
end
