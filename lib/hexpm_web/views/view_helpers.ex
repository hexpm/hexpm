defmodule HexpmWeb.ViewHelpers do
  use Phoenix.HTML
  alias Hexpm.Repository.{Package, Release}
  alias HexpmWeb.Endpoint
  alias HexpmWeb.Router.Helpers, as: Routes

  def logged_in?(assigns) do
    !!assigns[:current_user]
  end

  def package_name(package) do
    package_name(package.repository.name, package.name)
  end

  def package_name("hexpm", package) do
    package
  end

  def package_name(repository, package) do
    repository <> " / " <> package
  end

  def path_for_package(package) do
    if package.repository.id == 1 do
      Routes.package_path(Endpoint, :show, package, [])
    else
      Routes.package_path(Endpoint, :show, package.repository, package, [])
    end
  end

  def path_for_package("hexpm", package) do
    Routes.package_path(Endpoint, :show, package, [])
  end

  def path_for_package(repository, package) do
    Routes.package_path(Endpoint, :show, repository, package, [])
  end

  def path_for_release(package, release) do
    if package.repository.id == 1 do
      Routes.package_path(Endpoint, :show, package, release, [])
    else
      Routes.package_path(Endpoint, :show, package.repository, package, release, [])
    end
  end

  def path_for_releases(package) do
    if package.repository.id == 1 do
      Routes.version_path(Endpoint, :index, package, [])
    else
      Routes.version_path(Endpoint, :index, package.repository, package, [])
    end
  end

  def html_url_for_package(%Package{repository_id: 1} = package) do
    Routes.package_url(Endpoint, :show, package, [])
  end

  def html_url_for_package(%Package{} = package) do
    Routes.package_url(Endpoint, :show, package.repository, package, [])
  end

  def html_url_for_release(%Package{repository_id: 1} = package, release) do
    Routes.package_url(Endpoint, :show, package, release, [])
  end

  def html_url_for_release(%Package{} = package, release) do
    Routes.package_url(Endpoint, :show, package.repository, package, release, [])
  end

  def docs_html_url_for_package(package) do
    if Enum.any?(package.releases, & &1.has_docs) do
      Hexpm.Utils.docs_html_url(package.repository, package, nil)
    end
  end

  def docs_html_url_for_release(_package, %Release{has_docs: false}) do
    nil
  end

  def docs_html_url_for_release(package, release) do
    Hexpm.Utils.docs_html_url(package.repository, package, release)
  end

  def url_for_package(%Package{repository_id: 1} = package) do
    Routes.api_package_url(Endpoint, :show, package, [])
  end

  def url_for_package(package) do
    Routes.api_package_url(Endpoint, :show, package.repository, package, [])
  end

  def url_for_release(%Package{repository_id: 1} = package, release) do
    Routes.api_release_url(Endpoint, :show, package, release, [])
  end

  def url_for_release(%Package{} = package, release) do
    Routes.api_release_url(
      Endpoint,
      :show,
      package.repository,
      package,
      to_string(release.version),
      []
    )
  end

  def gravatar_url(nil, size) do
    "https://www.gravatar.com/avatar?s=#{gravatar_size(size)}&d=mm"
  end

  def gravatar_url(email, size) do
    hash =
      :crypto.hash(:md5, String.trim(email))
      |> Base.encode16(case: :lower)

    "https://www.gravatar.com/avatar/#{hash}?s=#{gravatar_size(size)}&d=retro"
  end

  defp gravatar_size(:large), do: 440
  defp gravatar_size(:small), do: 80

  def changeset_error(changeset) do
    if changeset.action do
      content_tag :div, class: "alert alert-danger" do
        "Oops, something went wrong! Please check the errors below."
      end
    end
  end

  def text_input(form, field, opts \\ []) do
    value = form.params[Atom.to_string(field)] || Map.get(form.data, field)

    opts =
      opts
      |> add_error_class(form, field)
      |> Keyword.put_new(:value, value)

    Phoenix.HTML.Form.text_input(form, field, opts)
  end

  def email_input(form, field, opts \\ []) do
    value = form.params[Atom.to_string(field)] || Map.get(form.data, field)

    opts =
      opts
      |> add_error_class(form, field)
      |> Keyword.put_new(:value, value)

    Phoenix.HTML.Form.email_input(form, field, opts)
  end

  def password_input(form, field, opts \\ []) do
    opts = add_error_class(opts, form, field)
    Phoenix.HTML.Form.password_input(form, field, opts)
  end

  def select(form, field, options, opts \\ []) do
    opts = add_error_class(opts, form, field)
    Phoenix.HTML.Form.select(form, field, options, opts)
  end

  defp add_error_class(opts, form, field) do
    error? = Keyword.has_key?(form.errors, field)
    error_class = if error?, do: "form-input-error", else: ""
    class = "form-control #{error_class} #{opts[:class]}"

    Keyword.put(opts, :class, class)
  end

  def error_tag(form, field) do
    if error = form.errors[field] do
      content_tag(:span, translate_error(error), class: "form-error")
    end
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, msg ->
      String.replace(msg, "%{#{key}}", to_string(value))
    end)
  end

  def paginate(page, count, opts) do
    per_page = opts[:items_per_page]
    # Needs to be odd number
    max_links = opts[:page_links]

    all_pages = div(count - 1, per_page) + 1
    middle_links = div(max_links, 2) + 1

    page_links =
      cond do
        page < middle_links ->
          Enum.take(1..max_links, all_pages)

        page > all_pages - middle_links ->
          start =
            if all_pages > middle_links + 1 do
              all_pages - (middle_links + 1)
            else
              1
            end

          Enum.to_list(start..all_pages)

        true ->
          Enum.to_list((page - 2)..(page + 2))
      end

    %{prev: page != 1, next: page != all_pages, page_links: page_links}
  end

  def params(list) do
    Enum.filter(list, fn {_, v} -> present?(v) end)
  end

  def present?(""), do: false
  def present?(nil), do: false
  def present?(_), do: true

  def text_length(text, length) when byte_size(text) > length do
    :binary.part(text, 0, length - 3) <> "..."
  end

  def text_length(text, _length) do
    text
  end

  def human_number_space(0, _max), do: "0"

  def human_number_space(int, max) when is_integer(int) do
    unit =
      cond do
        int >= 1_000_000_000 -> {"B", 9}
        int >= 1_000_000 -> {"M", 6}
        int >= 1_000 -> {"K", 3}
        true -> {"", 1}
      end

    do_human_number(int, max, trunc(:math.log10(int)) + 1, unit)
  end

  def human_number_space(number) do
    number
    |> to_string()
    |> String.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.intersperse(?\s)
    |> List.flatten()
    |> Enum.reverse()
    |> :erlang.list_to_binary()
  end

  defp do_human_number(int, max, digits, _unit) when is_integer(int) and digits <= max do
    human_number_space(int)
  end

  defp do_human_number(int, max, digits, {unit, mag}) when is_integer(int) and digits > max do
    shifted = int / :math.pow(10, mag)
    len = trunc(:math.log10(shifted)) + 2
    float = Float.round(shifted, max - len)

    case Float.ratio(float) do
      {_, 1} -> human_number_space(trunc(float)) <> unit
      {_, _} -> to_string(float) <> unit
    end
  end

  def human_relative_time_from_now(datetime) do
    ts = NaiveDateTime.to_erl(datetime) |> :calendar.datetime_to_gregorian_seconds()
    diff = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time()) - ts
    rel = rel_from_now(:calendar.seconds_to_daystime(diff))

    content_tag(:span, rel, title: pretty_date(datetime))
  end

  defp rel_from_now({0, {0, 0, sec}}) when sec < 30, do: "about now"
  defp rel_from_now({0, {0, min, _}}) when min < 2, do: "1 minute ago"
  defp rel_from_now({0, {0, min, _}}), do: "#{min} minutes ago"
  defp rel_from_now({0, {1, _, _}}), do: "1 hour ago"
  defp rel_from_now({0, {hour, _, _}}) when hour < 24, do: "#{hour} hours ago"
  defp rel_from_now({1, {_, _, _}}), do: "1 day ago"
  defp rel_from_now({day, {_, _, _}}) when day < 0, do: "about now"
  defp rel_from_now({day, {_, _, _}}), do: "#{day} days ago"

  def pretty_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y, %H:%M")
  end

  def pretty_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  def pretty_date(date, :short) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  def if_value(arg, nil, _fun), do: arg
  def if_value(arg, false, _fun), do: arg
  def if_value(arg, _true, fun), do: fun.(arg)

  def safe_join(enum, separator, fun \\ & &1) do
    Enum.map_join(enum, separator, &safe_to_string(fun.(&1)))
    |> raw()
  end

  def include_if_loaded(output, key, struct, view, name \\ "show.json", assigns \\ %{})

  def include_if_loaded(output, _key, %Ecto.Association.NotLoaded{}, _view, _name, _assigns) do
    output
  end

  def include_if_loaded(output, _key, nil, _view, _name, _assigns) do
    output
  end

  def include_if_loaded(output, key, struct, fun, _name, _assigns) when is_function(fun, 1) do
    Map.put(output, key, fun.(struct))
  end

  def include_if_loaded(output, key, structs, view, name, assigns) when is_list(structs) do
    Map.put(output, key, Phoenix.View.render_many(structs, view, name, assigns))
  end

  def include_if_loaded(output, key, struct, view, name, assigns) do
    Map.put(output, key, Phoenix.View.render_one(struct, view, name, assigns))
  end

  def auth_qr_code_svg(user) do
    "otpauth://totp/hex.pm:#{user.username}?issuer=hex.pm&secret=#{user.tfa.secret}"
    |> EQRCode.encode()
    |> EQRCode.svg(width: 250)
  end

  # assumes positive values only, and graph dimensions of 800 x 200
  def time_series_graph(points) do
    max =
      Enum.max(points ++ [5])
      |> rounded_max()

    y_axis_labels = y_axis_labels(0, max)

    calculated_points =
      points
      |> Enum.map(fn p -> points_to_graph(max, p) end)
      |> Enum.zip(x_axis_points(length(points)))

    polyline_points = to_polyline_points(calculated_points)
    polyline_fill = to_polyline_fill(calculated_points)

    {y_axis_labels, polyline_points, polyline_fill}
  end

  defp points_to_graph(max, data) do
    px_per_point = 200 / max
    198 - (data |> Kernel.*(px_per_point) |> Float.round(3))
  end

  defp x_axis_points(total_points) do
    # width / points captured
    px_per_point = Float.round(800 / total_points, 2)
    Enum.map(0..total_points, &Kernel.*(&1, px_per_point))
  end

  defp to_polyline_points(list) do
    Enum.reduce(list, "", fn {y, x}, acc -> acc <> "#{x}, #{y} " end)
  end

  defp to_polyline_fill(list) do
    top = Enum.reduce(list, "", fn {y, x}, acc -> acc <> "#{x}, #{y} " end)
    {_last_y, last_x} = List.last(list)
    fill = "#{last_x}, 200 0, 200"
    top <> fill
  end

  defp y_axis_labels(min, max) do
    div = (rounded_max(max) - min) / 5

    [
      min,
      round(div),
      round(div * 2),
      round(div * 3),
      round(div * 4)
    ]
  end

  defp rounded_max(max) do
    case max do
      max when max > 1_000_000 -> max |> Kernel./(1_000_000) |> ceil |> Kernel.*(1_000_000)
      max when max > 100_000 -> max |> Kernel./(100_000) |> ceil |> Kernel.*(100_000)
      max when max > 10_000 -> max |> Kernel./(10_000) |> ceil |> Kernel.*(10_000)
      max when max > 1_000 -> max |> Kernel./(1_000) |> ceil |> Kernel.*(1_000)
      max when max > 100 -> 1_000
      _ -> 100
    end
  end
end

defimpl Phoenix.HTML.Safe, for: Version do
  def to_iodata(version), do: String.Chars.Version.to_string(version)
end
