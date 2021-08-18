defmodule HexpmWeb.Dashboard.OrganizationView do
  use HexpmWeb, :view
  alias HexpmWeb.DashboardView

  defp organization_roles_selector() do
    Enum.map(organization_roles(), fn {name, id, _title} ->
      {name, id}
    end)
  end

  defp organization_roles() do
    [
      {"Admin", "admin", "This role has full control of the organization"},
      {"Write", "write", "This role has package owner access to all organization packages"},
      {"Read", "read", "This role can fetch all organization packages"}
    ]
  end

  defp organization_role(id) do
    Enum.find_value(organization_roles(), fn {name, organization_id, _title} ->
      if id == organization_id do
        name
      end
    end)
  end

  defp plan("organization-monthly"), do: "Organization, monthly billed ($7.00 per user / month)"
  defp plan("organization-annually"), do: "Organization, annually billed ($70.00 per user / year)"
  defp plan_price("organization-monthly"), do: "$7.00"
  defp plan_price("organization-annually"), do: "$70.00"

  defp proration_description("organization-monthly", price, days, quantity, quantity) do
    """
    Each new seat will be prorated on the next invoice for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """
    |> raw()
  end

  defp proration_description("organization-annually", price, days, quantity, quantity) do
    """
    Each new seat will be charged a proration for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """
    |> raw()
  end

  defp proration_description("organization-monthly", price, days, quantity, max_period_quantity)
       when quantity < max_period_quantity do
    """
    You have already used <strong>#{max_period_quantity}</strong> seats in your current billing period.
    If adding seats over this amount, each new seat will be prorated on the next invoice for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """
    |> raw()
  end

  defp proration_description("organization-annually", price, days, quantity, max_period_quantity)
       when quantity < max_period_quantity do
    """
    You have already used <strong>#{max_period_quantity}</strong> seats in your current billing period.
    If adding seats over this amount, each new seat will be charged a proration for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """
    |> raw()
  end

  @no_card_message "No payment method on file"

  defp payment_card(nil) do
    @no_card_message
  end

  defp payment_card(%{"brand" => nil}) do
    @no_card_message
  end

  defp payment_card(card) do
    card_exp_month = String.pad_leading(card["exp_month"], 2, "0")
    expires = "#{card_exp_month}/#{card["exp_year"]}"
    "#{card["brand"]} **** **** **** #{card["last4"]}, Expires: #{expires}"
  end

  defp subscription_status(%{"status" => "active", "cancel_at_period_end" => false}, _card) do
    "Active"
  end

  defp subscription_status(%{"status" => "active", "cancel_at_period_end" => true}, _card) do
    "Ends after current subscription period"
  end

  defp subscription_status(
         %{"status" => "trialing", "trial_end" => trial_end},
         card
       ) do
    trial_end = trial_end |> NaiveDateTime.from_iso8601!() |> ViewHelpers.pretty_date()
    raw("Trial ends on #{trial_end}, #{trial_status_message(card)}")
  end

  defp subscription_status(%{"status" => "past_due"}, _card) do
    "Active with past due invoice, if the invoice is not paid the " <>
      "organization will be disabled"
  end

  defp subscription_status(%{"status" => "incomplete"}, _card) do
    "TODO"
  end

  # TODO: Check if last invoice was unpaid and add note about it?
  defp subscription_status(%{"status" => "canceled"}, _card) do
    "Not active"
  end

  @trial_ends_no_card_message """
  your subscription will end after the trial period because we have no payment method on file for you,
  please enter a payment method if you wish to continue using organizations after the trial period
  """

  defp trial_status_message(%{"brand" => nil}) do
    @trial_ends_no_card_message
  end

  defp trial_status_message(nil) do
    @trial_ends_no_card_message
  end

  defp trial_status_message(_card) do
    "a payment method is on file and your subscription will continue after the trial period"
  end

  defp discount_status(nil) do
    ""
  end

  defp discount_status(%{"name" => name, "percent_off" => percent_off}) do
    "(\"#{name}\" discount for #{percent_off}% of price)"
  end

  defp invoice_status(%{"paid" => true}, _organization, _card), do: "Paid"
  defp invoice_status(%{"status" => "uncollectible"}, _organization, _card), do: "Forgiven"

  defp invoice_status(%{"paid" => false, "attempted" => false}, _organization, _card),
    do: "Pending"

  defp invoice_status(%{"paid" => false, "attempted" => true}, _organization, nil = _card) do
    submit(
      "Pay now",
      class: "btn btn-primary",
      disabled: true,
      title: "No payment method on file"
    )
  end

  defp invoice_status(
         %{"paid" => false, "attempted" => true, "id" => invoice_id},
         organization,
         _card
       ) do
    form_tag(Routes.organization_path(Endpoint, :pay_invoice, organization, invoice_id)) do
      submit("Pay now", class: "btn btn-primary")
    end
  end

  def payment_date(iso_8601_datetime_string) do
    iso_8601_datetime_string |> NaiveDateTime.from_iso8601!() |> ViewHelpers.pretty_date()
  end

  defp money(integer) when is_integer(integer) and integer >= 0 do
    whole = div(integer, 100)
    float = rem(integer, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{whole}.#{float}"
  end

  defp default_billing_emails(user, billing_email) do
    emails =
      user.emails
      |> Enum.filter(& &1.verified)
      |> Enum.map(& &1.email)

    [billing_email | emails]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
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
    # Czechia (Changed for Stripe compatibility)
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

  defp organization_admin?(current_user, organization) do
    user = Enum.find(organization.organization_users, &(&1.user_id == current_user.id))
    user.role == "admin"
  end
end
