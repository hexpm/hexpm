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

    tmp       Path.expand("tmp")
    url       System.get_env("HEX_URL") || "http://localhost:#{opts[:port]}"
    port      opts[:port]
    app_host  System.get_env("APP_HOST")
    use_ssl   match?("https://" <> _, url())
    store     (if System.get_env("S3_BUCKET"), do: HexWeb.Store.S3, else: HexWeb.Store.Local)

    s3_bucket     System.get_env("S3_BUCKET")
    s3_access_key System.get_env("S3_ACCESS_KEY")
    s3_secret_key System.get_env("S3_SECRET_KEY")
    cdn_url       System.get_env("CDN_URL")
  end

  var :tmp
  var :url
  var :port
  var :app_host
  var :use_ssl
  var :password_work_factor

  var :store
  var :s3_bucket
  var :s3_access_key
  var :s3_secret_key
  var :cdn_url
end
