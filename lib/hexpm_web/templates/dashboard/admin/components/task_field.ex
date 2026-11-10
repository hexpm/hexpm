defmodule HexpmWeb.Dashboard.Admin.Components.TaskField do
  @moduledoc """
  Renders one input of an admin task form, see `HexpmWeb.Dashboard.AdminView.sections/0`.
  Every value is posted as `args[<name>]`, and a text field starts with the
  value `prefill` has for its name.
  """
  use Phoenix.Component

  import HexpmWeb.Components.Input, only: [text_input: 1, textarea_input: 1, select_input: 1]

  alias Hexpm.AdminTasks

  attr :task, :map, required: true
  attr :field, :map, required: true
  attr :prefill, :map, default: %{}

  def task_field(%{field: %{kind: :text}} = assigns) do
    ~H"""
    <.text_input
      id={field_id(@task, @field.name)}
      name={field_name(@field.name)}
      type={@field.type}
      label={@field.label}
      required={@field.required}
      placeholder={@field.placeholder}
      value={Map.get(@prefill, @field.name, @field.value)}
      autocomplete={if @field.type == "password", do: "new-password", else: "off"}
    />
    """
  end

  def task_field(%{field: %{kind: :textarea}} = assigns) do
    ~H"""
    <div class="md:col-span-2">
      <.textarea_input
        id={field_id(@task, @field.name)}
        name={field_name(@field.name)}
        label={@field.label}
        required
        placeholder={@field.placeholder}
        rows={@field.rows}
      />
    </div>
    """
  end

  def task_field(%{field: %{kind: :select}} = assigns) do
    ~H"""
    <.select_input
      id={field_id(@task, @field.name)}
      name={field_name(@field.name)}
      label={@field.label}
      options={@field.options}
    />
    """
  end

  def task_field(%{field: %{kind: :checkbox}} = assigns) do
    ~H"""
    <label class="md:col-span-2 flex items-start gap-3 cursor-pointer">
      <input
        type="checkbox"
        id={field_id(@task, @field.name)}
        name={field_name(@field.name)}
        value="true"
        class="mt-0.5 w-4 h-4 text-purple-600 border-grey-300 dark:border-grey-600 rounded focus:ring-2 focus:ring-purple-500"
      />
      <span class="text-small text-grey-900 dark:text-grey-100">{@field.label}</span>
    </label>
    """
  end

  def task_field(%{field: %{kind: :reason}} = assigns) do
    assigns = assign(assigns, :options, reason_options(assigns.field.scope))

    ~H"""
    <.select_input
      id={field_id(@task, "reason")}
      name={field_name("reason")}
      label="Email a reason"
      options={@options}
    />
    <div class="md:col-span-2">
      <.textarea_input
        id={field_id(@task, "reason_text")}
        name={field_name("reason_text")}
        label="Or write the reason"
        placeholder="Sent instead of the reason picked above"
        rows="3"
      />
    </div>
    """
  end

  defp reason_options(scope) do
    [{"Don't send an email", ""}] ++
      Enum.map(AdminTasks.reasons(scope), fn {id, _text} ->
        {Phoenix.Naming.humanize(id), Atom.to_string(id)}
      end)
  end

  defp field_id(task, name), do: "#{task.id}-#{name}"
  defp field_name(name), do: "args[#{name}]"
end
