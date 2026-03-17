defmodule HexpmWeb.ViewHelpers do
  use PhoenixHTMLHelpers
  use HexpmWeb, :verified_routes
  import Phoenix.HTML
  alias Hexpm.Repository.{Package, Release}

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

  def path_for_package(%Package{repository_id: 1} = package) do
    ~p"/packages/#{package}"
  end

  def path_for_package(%Package{} = package) do
    ~p"/packages/#{package.repository}/#{package}"
  end

  def path_for_package("hexpm", package) do
    ~p"/packages/#{package}"
  end

  def path_for_package(repository, package) do
    ~p"/packages/#{repository}/#{package}"
  end

  def path_for_release(%Package{repository_id: 1} = package, release) do
    ~p"/packages/#{package}/#{release}"
  end

  def path_for_release(%Package{} = package, release) do
    ~p"/packages/#{package.repository}/#{package}/#{release}"
  end

  def path_for_releases(%Package{repository_id: 1} = package) do
    ~p"/packages/#{package}/versions"
  end

  def path_for_releases(%Package{} = package) do
    ~p"/packages/#{package.repository}/#{package}/versions"
  end

  def html_url_for_package(%Package{repository_id: 1} = package) do
    url(~p"/packages/#{package}")
  end

  def html_url_for_package(%Package{} = package) do
    url(~p"/packages/#{package.repository}/#{package}")
  end

  def html_url_for_release(%Package{repository_id: 1} = package, release) do
    url(~p"/packages/#{package}/#{release}")
  end

  def html_url_for_release(%Package{} = package, release) do
    url(~p"/packages/#{package.repository}/#{package}/#{release}")
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
    url(~p"/api/packages/#{package}")
  end

  def url_for_package(%Package{} = package) do
    url(~p"/api/repos/#{package.repository}/packages/#{package}")
  end

  def url_for_release(%Package{repository_id: 1} = package, release) do
    url(~p"/api/packages/#{package}/releases/#{release}")
  end

  def url_for_release(%Package{} = package, release) do
    url(~p"/api/repos/#{package.repository}/packages/#{package}/releases/#{release}")
  end

  def gravatar_url(nil, size) do
    "https://www.gravatar.com/avatar/00000000000000000000000000000000?s=#{gravatar_size(size)}&d=mp"
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

    PhoenixHTMLHelpers.Form.text_input(form, field, opts)
  end

  def email_input(form, field, opts \\ []) do
    value = form.params[Atom.to_string(field)] || Map.get(form.data, field)

    opts =
      opts
      |> add_error_class(form, field)
      |> Keyword.put_new(:value, value)

    PhoenixHTMLHelpers.Form.email_input(form, field, opts)
  end

  def password_input(form, field, opts \\ []) do
    opts = add_error_class(opts, form, field)
    PhoenixHTMLHelpers.Form.password_input(form, field, opts)
  end

  def select(form, field, options, opts \\ []) do
    opts = add_error_class(opts, form, field)
    PhoenixHTMLHelpers.Form.select(form, field, options, opts)
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

  def params(enum1, enum2) do
    map1 = Map.new(enum1)
    map2 = Map.new(enum2)

    Map.merge(map1, map2)
    |> Enum.filter(fn {_, v} -> present?(v) end)
  end

  def params(enum) do
    Enum.filter(enum, fn {_, v} -> present?(v) end)
  end

  defp present?(""), do: false
  defp present?(nil), do: false
  defp present?(_), do: true

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

  def human_number_compact(nil), do: "0"
  def human_number_compact(n) when n >= 1_000_000_000, do: format_compact(n / 1_000_000_000, "B")
  def human_number_compact(n) when n >= 1_000_000, do: format_compact(n / 1_000_000, "M")
  def human_number_compact(n) when n >= 1_000, do: format_compact(n / 1_000, "K")
  def human_number_compact(n), do: "#{n}"

  defp format_compact(value, unit) do
    rounded = Float.round(value, 1)

    case Float.ratio(rounded) do
      {_, 1} -> "#{trunc(rounded)}#{unit}"
      {_, _} -> "#{rounded}#{unit}"
    end
  end

  defp do_human_number(int, max, digits, _unit) when is_integer(int) and digits <= max do
    human_number_space(int)
  end

  defp do_human_number(int, max, digits, {unit, mag}) when is_integer(int) and digits > max do
    shifted = int / :math.pow(10, mag)
    len = trunc(:math.log10(shifted)) + 2
    precision = max(0, max - len)
    float = Float.round(shifted, precision)

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

  def auth_qr_code_svg(user, secret) do
    "otpauth://totp/hex.pm:#{user.username}?issuer=hex.pm&secret=#{secret}"
    |> EQRCode.encode()
    |> EQRCode.svg(width: 250)
    |> convert_svg_inline_styles_to_attributes()
  end

  # Convert inline styles in SVG to presentation attributes for CSP compliance
  # See: https://github.com/SiliconJungles/eqrcode/issues/33
  defp convert_svg_inline_styles_to_attributes(svg) do
    svg
    # Convert style="fill: #XXX;" to fill="#XXX"
    |> String.replace(~r/style="fill:\s*([^;"]+);?"/, "fill=\"\\1\"")
    # Convert style="background-color: #XXX" on svg element to a rect background
    |> String.replace(
      ~r/<svg([^>]*)\s+style="background-color:\s*([^"]+)"([^>]*)>/,
      "<svg\\1\\3><rect width=\"100%\" height=\"100%\" fill=\"\\2\"/>"
    )
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

    # Convert {y, x} tuples to {x, y} for path generation
    xy_points = Enum.map(calculated_points, fn {y, x} -> {x, y} end)

    line_path = to_smooth_path(xy_points)
    fill_path = to_smooth_fill(xy_points)

    {y_axis_labels, line_path, fill_path}
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

  @smoothing 0.2

  defp to_smooth_path(points) do
    [{x0, y0} | _] = points
    segments = smooth_segments(points)
    "M#{x0},#{y0}" <> Enum.join(segments)
  end

  defp to_smooth_fill(points) do
    [{x0, y0} | _] = points
    {xn, _yn} = List.last(points)
    segments = smooth_segments(points)
    "M#{x0},#{y0}" <> Enum.join(segments) <> "L#{xn},200L0,200Z"
  end

  defp smooth_segments(points) do
    indexed = Enum.with_index(points)

    Enum.map(indexed, fn {{_x, _y}, i} ->
      if i == length(points) - 1 do
        ""
      else
        {x1, y1} = Enum.at(points, i)
        {x2, y2} = Enum.at(points, i + 1)

        {px0, py0} = if i > 0, do: Enum.at(points, i - 1), else: {x1, y1}
        {px3, py3} = if i + 2 < length(points), do: Enum.at(points, i + 2), else: {x2, y2}

        cp1x = Float.round(x1 + (x2 - px0) * @smoothing, 2)
        cp1y = Float.round(y1 + (y2 - py0) * @smoothing, 2) |> max(0.0) |> min(198.0)
        cp2x = Float.round(x2 - (px3 - x1) * @smoothing, 2)
        cp2y = Float.round(y2 - (py3 - y1) * @smoothing, 2) |> max(0.0) |> min(198.0)

        "C#{cp1x},#{cp1y} #{cp2x},#{cp2y} #{x2},#{y2}"
      end
    end)
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

  def main_repository?(%{repository_id: 1}), do: true
  def main_repository?(_), do: false

  def readme_url(package_name, version) do
    readme_url = Application.fetch_env!(:hexpm, :readme_url)
    "#{readme_url}/#{package_name}/#{version}"
  end

  def safe_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https", "mailto"] -> url
      _ -> "#"
    end
  end

  def safe_url(_), do: "#"
end

defimpl Phoenix.HTML.Safe, for: Version do
  def to_iodata(version), do: String.Chars.Version.to_string(version)
end
