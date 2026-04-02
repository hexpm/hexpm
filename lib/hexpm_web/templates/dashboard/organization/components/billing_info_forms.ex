defmodule HexpmWeb.Dashboard.Organization.Components.BillingInfoForms do
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  alias Phoenix.LiveView.JS
  alias HexpmWeb.Dashboard.Organization.Components.BillingHelpers
  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1, select_input: 1]

  attr :organization, :map, required: true
  attr :billing_started?, :boolean, default: false
  attr :billing_email, :string, default: nil
  attr :person, :map, default: nil
  attr :company, :map, default: nil
  attr :params, :map, default: %{}
  attr :errors, :map, default: %{}
  attr :current_user, :map, required: true

  def billing_info_forms(assigns) do
    errors = assigns.errors || %{}
    person = assigns.person || %{}
    company = assigns.company || %{}

    # Preserve active tab on validation errors — same logic as the old EEX partials
    initial_tab =
      cond do
        errors["company"] && !errors["person"] -> "company"
        company != %{} && !errors["person"] && person == %{} -> "company"
        true -> "person"
      end

    assigns =
      assigns
      |> assign(:params, assigns.params || %{})
      |> assign(:errors, errors)
      |> assign(:person, person)
      |> assign(:company, company)
      |> assign(:initial_tab, initial_tab)

    ~H"""
    <div class="bg-white border border-grey-200 rounded-lg overflow-hidden">
      <div class="px-6 py-5 border-b border-grey-200">
        <h2 class="text-grey-900 text-lg font-semibold">Billing information</h2>
      </div>
      <div class="px-6 py-5">
        <div class="flex gap-4 border-b border-grey-200 mb-6">
          <.billing_tab_btn
            id="billing-tab-btn-person"
            active={@initial_tab == "person"}
            phx-click={
              JS.show(to: "#billing-panel-person")
              |> JS.hide(to: "#billing-panel-company")
              |> JS.add_class("border-purple-600 text-purple-600", to: "#billing-tab-btn-person")
              |> JS.remove_class("border-transparent text-grey-500", to: "#billing-tab-btn-person")
              |> JS.remove_class("border-purple-600 text-purple-600", to: "#billing-tab-btn-company")
              |> JS.add_class("border-transparent text-grey-500", to: "#billing-tab-btn-company")
            }
          >
            Person
          </.billing_tab_btn>
          <.billing_tab_btn
            id="billing-tab-btn-company"
            active={@initial_tab == "company"}
            phx-click={
              JS.show(to: "#billing-panel-company")
              |> JS.hide(to: "#billing-panel-person")
              |> JS.add_class("border-purple-600 text-purple-600", to: "#billing-tab-btn-company")
              |> JS.remove_class("border-transparent text-grey-500", to: "#billing-tab-btn-company")
              |> JS.remove_class("border-purple-600 text-purple-600", to: "#billing-tab-btn-person")
              |> JS.add_class("border-transparent text-grey-500", to: "#billing-tab-btn-person")
            }
          >
            Company
          </.billing_tab_btn>
        </div>

        <div id="billing-panel-person" class={if @initial_tab != "person", do: "hidden"}>
          <.sudo_form
            current_user={@current_user}
            action={billing_form_path(@organization, @billing_started?)}
          >
            <.person_fields
              billing_email={@billing_email}
              current_user={@current_user}
              errors={@errors}
              params={@params}
              person={@person}
            />
            <div class="mt-6">
              <.button type="submit" variant="primary">Save</.button>
            </div>
          </.sudo_form>
        </div>

        <div id="billing-panel-company" class={if @initial_tab != "company", do: "hidden"}>
          <.sudo_form
            current_user={@current_user}
            action={billing_form_path(@organization, @billing_started?)}
          >
            <.company_fields
              billing_email={@billing_email}
              current_user={@current_user}
              errors={@errors}
              params={@params}
              company={@company}
            />
            <div class="mt-6">
              <.button type="submit" variant="primary">Save</.button>
            </div>
          </.sudo_form>
        </div>
      </div>
    </div>
    """
  end

  attr :active, :boolean, default: false
  attr :id, :string, required: true
  attr :rest, :global, include: ~w(phx-click)
  slot :inner_block, required: true

  defp billing_tab_btn(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      class={[
        "pb-3 text-sm font-medium border-b-2 transition-colors",
        if(@active,
          do: "border-purple-600 text-purple-600",
          else: "border-transparent text-grey-500 hover:text-grey-700"
        )
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp billing_form_path(organization, true),
    do: ~p"/dashboard/orgs/#{organization}/update-billing"

  defp billing_form_path(organization, _),
    do: ~p"/dashboard/orgs/#{organization}/create-billing"

  attr :billing_email, :string, default: nil
  attr :current_user, :map, required: true
  attr :errors, :map, default: %{}
  attr :params, :map, default: %{}
  attr :person, :map, default: %{}

  defp person_fields(assigns) do
    person_params = assigns.params["person"] || %{}
    person_errors = assigns.errors["person"] || %{}

    assigns =
      assigns
      |> assign(
        :emails,
        BillingHelpers.default_billing_emails(assigns.current_user, assigns.billing_email)
      )
      |> assign(:person_params, person_params)
      |> assign(:person_errors, person_errors)
      |> assign(:country_options, Enum.map(countries(), fn {code, name} -> {name, code} end))

    ~H"""
    <div class="space-y-4">
      <.text_input
        id="person-billing-email"
        name="email"
        label="Billing email"
        required
        value={@params["email"] || @billing_email}
        list="person-billing-emails"
        errors={List.wrap(@errors["email"])}
      />
      <datalist id="person-billing-emails">
        <%= for email <- @emails do %>
          <option value={email} />
        <% end %>
      </datalist>
      <.select_input
        id="person-country"
        name="person[country]"
        label="Country"
        required
        options={@country_options}
        value={@person_params["country"] || @person["country"]}
        errors={List.wrap(@person_errors["country"])}
      />
    </div>
    """
  end

  attr :billing_email, :string, default: nil
  attr :current_user, :map, required: true
  attr :params, :map, default: %{}
  attr :company, :map, default: %{}
  attr :errors, :map, default: %{}

  defp company_fields(assigns) do
    co_errors = assigns.errors["company"] || %{}

    assigns =
      assigns
      |> assign(
        :emails,
        BillingHelpers.default_billing_emails(assigns.current_user, assigns.billing_email)
      )
      |> assign(:co, assigns.company || %{})
      |> assign(:cp, assigns.params["company"] || %{})
      |> assign(:co_errors, co_errors)
      |> assign(:country_options, Enum.map(countries(), fn {code, name} -> {name, code} end))

    ~H"""
    <div class="space-y-4">
      <.text_input
        id="company-billing-email"
        name="email"
        label="Billing email"
        required
        value={@params["email"] || @billing_email}
        list="company-billing-emails"
        errors={List.wrap(@errors["email"])}
      />
      <datalist id="company-billing-emails">
        <%= for email <- @emails do %>
          <option value={email} />
        <% end %>
      </datalist>

      <.text_input
        id="company-name"
        name="company[name]"
        label="Company name"
        required
        value={@cp["name"] || @co["name"]}
        errors={List.wrap(@co_errors["name"])}
      />

      <.text_input
        id="company-vat"
        name="company[vat]"
        label="VAT number (EU companies only)"
        value={@cp["vat"] || @co["vat"]}
        errors={List.wrap(@co_errors["vat"])}
      />

      <div>
        <span class="block text-sm font-medium text-grey-700 mb-1">Address</span>
        <div class="grid grid-cols-2 gap-3">
          <.text_input
            id="company-address-line1"
            name="company[address_line1]"
            placeholder="Line 1"
            required
            value={@cp["address_line1"] || @co["address_line1"]}
            errors={List.wrap(@co_errors["address"])}
          />
          <.text_input
            id="company-address-line2"
            name="company[address_line2]"
            placeholder="Line 2"
            value={@cp["address_line2"] || @co["address_line2"]}
          />
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <.text_input
          id="company-zip"
          name="company[address_zip]"
          label="Zip code"
          required
          value={@cp["address_zip"] || @co["address_zip"]}
          errors={List.wrap(@co_errors["zip_code"])}
        />
        <.text_input
          id="company-city"
          name="company[address_city]"
          label="City"
          required
          value={@cp["address_city"] || @co["address_city"]}
          errors={List.wrap(@co_errors["city"])}
        />
      </div>

      <.text_input
        id="company-state"
        name="company[address_state]"
        label="State (optional)"
        value={@cp["address_state"] || @co["address_state"]}
      />

      <.select_input
        id="company-country"
        name="company[address_country]"
        label="Country"
        required
        options={@country_options}
        value={@cp["address_country"] || @co["address_country"]}
        errors={List.wrap(@co_errors["country"])}
      />
    </div>
    """
  end

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
    {"PS", "Palestine"},
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
end
