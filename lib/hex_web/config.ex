defmodule HexWeb.Config.DSL do
  defmacro var(name) do
    quote bind_quoted: binding do
      app_var = :"config_#{name}"
      def unquote(name)() do
        { :ok, value } = :application.get_env(:hex_web, unquote(app_var))
        value
      end

      def unquote(name)(value) do
        :application.set_env(:hex_web, unquote(app_var), value)
      end
    end
  end
end

defmodule HexWeb.Config do
  import HexWeb.Config.DSL

  def init(opts) do
    if url = System.get_env("HEX_URL") do
      url(url)
    else
      url("http://localhost:#{opts[:port]}")
    end

    url       System.get_env("HEX_URL") || "http://localhost:#{opts[:port]}"
    app_host  System.get_env("APP_HOST")
    use_ssl   match?("https://" <> _, url())
  end

  var :url
  var :app_host
  var :use_ssl
  var :password_work_factor
end
