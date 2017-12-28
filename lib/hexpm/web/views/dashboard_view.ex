defmodule Hexpm.Web.DashboardView do
  use Hexpm.Web, :view

  defp account_settings() do
    [
      profile: "Profile",
      password: "Password",
      email: "Email"
    ]
  end

  defp selected_setting(conn, id) do
    if Enum.take(conn.path_info, -2) == ["dashboard", Atom.to_string(id)] do
      "selected"
    end
  end

  defp selected_repository(conn, name) do
    if Enum.take(conn.path_info, -2) == ["repos", name] do
      "selected"
    end
  end

  defp public_email_options(user) do
    emails =
      user.emails
      |> Email.order_emails()
      |> Enum.filter(& &1.verified)
      |> Enum.map(&{&1.email, &1.email})

    [{"Don't show a public email address", "none"}] ++ emails
  end

  defp public_email_value(user) do
    User.email(user, :public) || "none"
  end

  def gravatar_email_options(user) do
    emails =
      user.emails
      |> Enum.filter(& &1.verified)
      |> Enum.map(&{&1.email, &1.email})

    [{"Don't show an avatar", "none"}] ++ emails
  end

  def gravatar_email_value(user) do
    User.email(user, :gravatar) || "none"
  end

  defp repository_roles_selector() do
    Enum.map(repository_roles(), fn {name, id, _title} ->
      {name, id}
    end)
  end

  defp repository_roles() do
    [
      {"Admin", "admin", "This role has full control of the repository"},
      {"Write", "write", "This role has package owner access to all repository packages"},
      {"Read", "read", "This role can fetch all repository packages"}
    ]
  end

  defp repository_role(id) do
    Enum.find_value(repository_roles(), fn {name, repository_id, _title} ->
      if id == repository_id do
        name
      end
    end)
  end

  defp payment_card(card) do
    card_exp_month = String.pad_leading(card["exp_month"], 2, "0")
    expires = "#{card_exp_month}/#{card["exp_year"]}"
    "#{card["brand"]} **** **** **** #{card["last4"]}, Expires: #{expires}"
  end

  defp subscription_status(%{"status" => "active", "cancel_at_period_end" => false}) do
    "Active"
  end
  defp subscription_status(%{"status" => "active", "cancel_at_period_end" => true}) do
    "Ends after current subscription period"
  end
  defp subscription_status(%{"status" => "past_due"}) do
    "Active with past due invoice, if the invoice is not paid the " <>
      "organization will be disabled"
  end
  # TODO: Check if last invoice was unpaid and add note about it?
  defp subscription_status(%{"status" => "canceled"}) do
    "Not active"
  end

  defp invoice_status(%{"paid" => true}), do: "Paid"
  defp invoice_status(%{"paid" => false, "attempted" => true}), do: "Past due"
  defp invoice_status(%{"paid" => false, "attempted" => false}), do: "Pending"

  def payment_date(date) do
    date |> NaiveDateTime.from_iso8601!() |> pretty_date()
  end

  defp money(integer) when is_integer(integer) and integer >= 0 do
    whole = div(integer, 100)
    float = rem(integer, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{whole}.#{float}"
  end

  defp billing_emails(user, billing_email) do
    emails =
      user.emails
      |> Enum.filter(& &1.verified)
      |> Enum.map(& &1.email)

    Enum.uniq([billing_email | emails])
  end

  # From Hexpm.Billing.Country
  @country_codes [
    {"AD", "Andorra"},
    {"AE", "United Arab Emirates"},
    {"AF", "Afghanistan"},
    {"AG", "Antigua and Barbuda"},
    {"AI", "Anguilla"},
    {"AL", "Albania"},
    {"AM", "Armenia"},
    {"AO", "Angola"},
    {"AQ", "Antarctica"},
    {"AR", "Argentina"},
    {"AS", "American Samoa"},
    {"AT", "Austria"},
    {"AU", "Australia"},
    {"AW", "Aruba"},
    {"AX", "Åland Islands"},
    {"AZ", "Azerbaijan"},
    {"BA", "Bosnia and Herzegovina"},
    {"BB", "Barbados"},
    {"BD", "Bangladesh"},
    {"BE", "Belgium"},
    {"BF", "Burkina Faso"},
    {"BG", "Bulgaria"},
    {"BH", "Bahrain"},
    {"BI", "Burundi"},
    {"BJ", "Benin"},
    {"BL", "Saint Barthélemy"},
    {"BM", "Bermuda"},
    # Brunei Darussalam
    {"BN", "Brunei"},
    # Bolivia, Plurinational State
    {"BO", "Bolivia"},
    # Bonaire, Sint Eustatius and Saba
    {"BQ", "Bonaire"},
    {"BR", "Brazil"},
    {"BS", "Bahamas"},
    {"BT", "Bhutan"},
    {"BV", "Bouvet Island"},
    {"BW", "Botswana"},
    {"BY", "Belarus"},
    {"BZ", "Belize"},
    {"CA", "Canada"},
    {"CC", "Cocos (Keeling) Islands"},
    {"CD", "Congo, the Democratic Republic of the"},
    {"CF", "Central African Republic"},
    {"CG", "Congo"},
    {"CH", "Switzerland"},
    {"CI", "Côte d'Ivoire"},
    {"CK", "Cook Islands"},
    {"CL", "Chile"},
    {"CM", "Cameroon"},
    {"CN", "China"},
    {"CO", "Colombia"},
    {"CR", "Costa Rica"},
    {"CU", "Cuba"},
    {"CV", "Cabo Verde"},
    {"CW", "Curaçao"},
    {"CX", "Christmas Island"},
    {"CY", "Cyprus"},
    # Czechia (Changed for Stripe compatability)
    {"CZ", "Czech Republic"},
    {"DE", "Germany"},
    {"DJ", "Djibouti"},
    {"DK", "Denmark"},
    {"DM", "Dominica"},
    {"DO", "Dominican Republic"},
    {"DZ", "Algeria"},
    {"EC", "Ecuador"},
    {"EE", "Estonia"},
    {"EG", "Egypt"},
    {"EH", "Western Sahara"},
    {"ER", "Eritrea"},
    {"ES", "Spain"},
    {"ET", "Ethiopia"},
    {"FI", "Finland"},
    {"FJ", "Fiji"},
    # Falkland Islands (Malvinas)
    {"FK", "Falkland Island"},
    # Micronesia, Federated States of
    {"FM", "Micronesia"},
    {"FO", "Faroe Islands"},
    {"FR", "France"},
    {"GA", "Gabon"},
    # United Kingdom of Great Britain and Northern Ireland
    {"GB", "United Kingdom"},
    {"GD", "Grenada"},
    {"GE", "Georgia"},
    {"GF", "French Guiana"},
    {"GG", "Guernsey"},
    {"GH", "Ghana"},
    {"GI", "Gibraltar"},
    {"GL", "Greenland"},
    {"GM", "Gambia"},
    {"GN", "Guinea"},
    {"GP", "Guadeloupe"},
    {"GQ", "Equatorial Guinea"},
    {"GR", "Greece"},
    # South Georgia and the South Sandwich Islands
    {"GS", "South Georgia"},
    {"GT", "Guatemala"},
    {"GU", "Guam"},
    {"GW", "Guinea-Bissau"},
    {"GY", "Guyana"},
    {"HK", "Hong Kong"},
    {"HM", "Heard Island and McDonald Islands"},
    {"HN", "Honduras"},
    {"HR", "Croatia"},
    {"HT", "Haiti"},
    {"HU", "Hungary"},
    {"ID", "Indonesia"},
    {"IE", "Ireland"},
    {"IL", "Israel"},
    {"IM", "Isle of Man"},
    {"IN", "India"},
    {"IO", "British Indian Ocean Territory"},
    {"IQ", "Iraq"},
    # Iran, Islamic Republic
    {"IR", "Iran"},
    {"IS", "Iceland"},
    {"IT", "Italy"},
    {"JE", "Jersey"},
    {"JM", "Jamaica"},
    {"JO", "Jordan"},
    {"JP", "Japan"},
    {"KE", "Kenya"},
    {"KG", "Kyrgyzstan"},
    {"KH", "Cambodia"},
    {"KI", "Kiribati"},
    {"KM", "Comoros"},
    {"KN", "Saint Kitts and Nevis"},
    {"KP", "Korea, Democratic People's Republic of"},
    {"KR", "Korea, Republic of"},
    {"KW", "Kuwait"},
    {"KY", "Cayman Islands"},
    {"KZ", "Kazakhstan"},
    # Lao People's Democratic Republic
    {"LA", "Laos"},
    {"LB", "Lebanon"},
    {"LC", "Saint Lucia"},
    {"LI", "Liechtenstein"},
    {"LK", "Sri Lanka"},
    {"LR", "Liberia"},
    {"LS", "Lesotho"},
    {"LT", "Lithuania"},
    {"LU", "Luxembourg"},
    {"LV", "Latvia"},
    {"LY", "Libya"},
    {"MA", "Morocco"},
    {"MC", "Monaco"},
    {"MD", "Moldova , Republic"},
    {"ME", "Montenegro"},
    # Saint Martin (French part)
    {"MF", "Saint Martin"},
    {"MG", "Madagascar"},
    {"MH", "Marshall Islands"},
    {"MK", "Macedonia"},
    {"ML", "Mali"},
    {"MM", "Myanmar"},
    {"MN", "Mongolia"},
    {"MO", "Macao"},
    {"MP", "Northern Mariana Islands"},
    {"MQ", "Martinique"},
    {"MR", "Mauritania"},
    {"MS", "Montserrat"},
    {"MT", "Malta"},
    {"MU", "Mauritius"},
    {"MV", "Maldives"},
    {"MW", "Malawi"},
    {"MX", "Mexico"},
    {"MY", "Malaysia"},
    {"MZ", "Mozambique"},
    {"NA", "Namibia"},
    {"NC", "New Caledonia"},
    {"NE", "Niger"},
    {"NF", "Norfolk Island"},
    {"NG", "Nigeria"},
    {"NI", "Nicaragua"},
    {"NL", "Netherlands"},
    {"NO", "Norway"},
    {"NP", "Nepal"},
    {"NR", "Nauru"},
    {"NU", "Niue"},
    {"NZ", "New Zealand"},
    {"OM", "Oman"},
    {"PA", "Panama"},
    {"PE", "Peru"},
    {"PF", "French Polynesia"},
    {"PG", "Papua New Guinea"},
    {"PH", "Philippines"},
    {"PK", "Pakistan"},
    {"PL", "Poland"},
    {"PM", "Saint Pierre and Miquelon"},
    {"PN", "Pitcairn"},
    {"PR", "Puerto Rico"},
    # Palestine, State of
    {"PS", "Palestin"},
    {"PT", "Portugal"},
    {"PW", "Palau"},
    {"PY", "Paraguay"},
    {"QA", "Qatar"},
    {"RE", "Réunion"},
    {"RO", "Romania"},
    {"RS", "Serbia"},
    # Russian Federation
    {"RU", "Russia"},
    {"RW", "Rwanda"},
    {"SA", "Saudi Arabia"},
    {"SB", "Solomon Islands"},
    {"SC", "Seychelles"},
    {"SD", "Sudan"},
    {"SE", "Sweden"},
    {"SG", "Singapore"},
    {"SH", "Saint Helena, Ascension and Tristan da Cunha"},
    {"SI", "Slovenia"},
    {"SJ", "Svalbard and Jan Mayen"},
    {"SK", "Slovakia"},
    {"SL", "Sierra Leone"},
    {"SM", "San Marino"},
    {"SN", "Senegal"},
    {"SO", "Somalia"},
    {"SR", "Suriname"},
    {"SS", "South Sudan"},
    {"ST", "Sao Tome and Principe"},
    {"SV", "El Salvador"},
    # Sint Maarten (Dutch part)
    {"SX", "Sint Maarten"},
    # Syrian Arab Republic
    {"SY", "Syria"},
    {"SZ", "Swaziland"},
    {"TC", "Turks and Caicos Islands"},
    {"TD", "Chad"},
    {"TF", "French Southern Territories"},
    {"TG", "Togo"},
    {"TH", "Thailand"},
    {"TJ", "Tajikistan"},
    {"TK", "Tokelau"},
    {"TL", "Timor-Leste"},
    {"TM", "Turkmenistan"},
    {"TN", "Tunisia"},
    {"TO", "Tonga"},
    {"TR", "Turkey"},
    {"TT", "Trinidad and Tobago"},
    {"TV", "Tuvalu"},
    # Taiwan, Province of China
    {"TW", "Taiwan"},
    # Tanzania, United Republic of
    {"TZ", "Tanzania"},
    {"UA", "Ukraine"},
    {"UG", "Uganda"},
    {"UM", "United States Minor Outlying Islands"},
    # United States of America
    {"US", "United States"},
    {"UY", "Uruguay"},
    {"UZ", "Uzbekistan"},
    {"VA", "Holy See"},
    {"VC", "Saint Vincent and the Grenadines"},
    # Venezuela, Bolivarian Republic of
    {"VE", "Venezuela"},
    # Virgin Islands, British
    {"VG", "British Virgin Islands"},
    # Virgin Islands, U.S.
    {"VI", "United States Virgin Islands"},
    {"VN", "Viet Nam"},
    {"VU", "Vanuatu"},
    {"WF", "Wallis and Futuna"},
    {"WS", "Samoa"},
    {"YE", "Yemen"},
    {"YT", "Mayotte"},
    {"ZA", "South Africa"},
    {"ZM", "Zambia"},
    {"ZW", "Zimbabwe"}
  ]

  defp countries() do
    unquote([{"", ""}] ++ Enum.sort_by(@country_codes, &elem(&1, 1)))
  end

  defp show_person?(person, errors) do
    (person || errors["person"]) && !errors["company"]
  end

  defp show_company?(company, errors) do
    (company || errors["company"]) && !errors["person"]
  end
end
