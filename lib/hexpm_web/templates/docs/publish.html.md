## Publishing a package

Publishing a package to Hex consists of registering a Hex user, adding metadata to the project's `mix.exs` file, and finally submitting the package with a `mix` task.

### Registering a Hex user

When registering a user, you will be prompted for a username, your email and a password. The email is used to confirm your identity during signup, as well as to contact you in case there is an issue with one of your packages. The email will never be shared with a third party.

```nohighlight
$ mix hex.user register
Username: johndoe
Email: john.doe@example.com
Password:
Password (confirm):
Registering...
Generating API key...
You are required to confirm your email to access your account, a confirmation email has been sent to john.doe@example.com
```

Once this step has been completed, check your email inbox for the confirmation email. Once you have followed the enclosed link, your account will be ready to use.

### Naming your package

Before publishing, you will have to choose the name of your package. Remember that packages published to Hex are public and can be accessed by anyone in the community. It is also the responsibility of the community to pick and encourage good package names. Here are some tips:

  * Avoid using offensive or harassing package names, nicknames, or other identifiers that might detract from a friendly, safe, and welcoming environment for all.
  * If you are providing functionality on top of an existing package, consider using that package name as a prefix. For example, if you want to add authentication to [Plug](https://github.com/elixir-lang/plug), consider calling your package `plug_auth` (or `plug_somename`) instead of `auth` (or `somename`).
  * Avoid namespace conflicts with existing packages. Plug owns the `Plug` namespace, if you have an authentication package for Plug use the namespace `PlugAuth` instead of `Plug.Auth`.
    * This guidelines holds for all of your modules, so if your package is `plug_auth` then all of your modules (except for special ones like mix tasks) should start with `PlugAuth.` (e.g. `PlugAuth.Utils`, `PlugAuth.User`). This is important because there can only be one module with a given name running in a BEAM system, and if multiple packages define the same module, then you cannot use both packages because only one version of the module will be used.

With a name in hand, it is time to add the proper metadata to your `mix.exs` file.

### Adding metadata to `mix.exs`

The package is configured in the `project` function in the project's `mix.exs` file. [See below](#example-mixexs-file) for an example file.

First, make sure that the `:version` property is correct. All Hex packages are required to follow [semantic versioning](http://semver.org/). While your package version is at major version "0", any breaking changes should be indicated by incrementing the minor version. For example, `0.1.0 -> 0.2.0`.

Fill in the `:description` property. It should be a sentence, or a few sentences, describing the package.

Under the `:package` property are some additional configuration options:

<dl class="dl-horizontal">
  <dt><code>:name</code></dt>
  <dd>The name of the package in case you want to publish the package with a different name than the application name. By default this is set to the same as the name of your OTP application (having the same value as `project.app`), written in snake_case (lowercase with underscores as word separator).</dd>
  <dt><code>:organization</code></dt>
  <dd>The organization the package belongs to. The package will be published to the organization repository, defaults to the global <code>"hexpm"</code> repository.</dd>
  <dt><code>:licenses</code></dt>
  <dd>A list of licenses the project is licensed under. This attribute is required. Valid license identifiers are available from <a href="https://spdx.org/licenses/">SPDX</a>.</dd>
  <dt><code>:links</code></dt>
  <dd>A map where the key is a link name and the value is the link URL. Optional but highly recommended.</dd>
  <dt><code>:files</code></dt>
  <dd>A list of files and directories to include in the package. Defaults to standard project directories, so you usually don't need to set this property.</dd>
  <dt><code>:build_tools</code></dt>
  <dd>List of build tools that can build the package. It's very rare that you need to set this, as Hex tries to automatically detect the build tools based on the files in the package. If a <code>rebar</code> or <code>rebar.config</code> file is present Hex will mark it as able to build with rebar. This detection can be overridden by setting this field.</dd>
</dl>

To improve the documentation generated by ExDoc, the following fields can also be supplied as part of the `project` function:

<dl class="dl-horizontal">
  <dt><code>:source_url</code></dt>
  <dd>An URL to the location where your source code is publicly available. This will be used to link directly to the code of the different modules functions from within the documentation.</dd>
  <dt><code>:homepage_url</code></dt>
  <dd>An URL to the homepage of your application. This will be used to link back to your homepage from within the generated documentation.</dd>
</dl>

Consult the [ExDoc documentation](https://github.com/elixir-lang/ex_doc#using-exdoc-with-mix) for more information on improving the generated documentation.

#### Dependencies

A dependency defined with no SCM (`:git` or `:path`) will be automatically treated as a Hex dependency. See the [Usage guide](/docs/usage) for more details.

Only Hex packages may be used as dependencies of the package. It is not possible to upload packages with Git dependencies. Additionally, only production dependencies will be included, just like how Mix will only fetch production dependencies when fetching the dependencies of your dependencies. Dependencies will be treated as production dependencies when they are defined with no `:only` property or with `only: :prod`.

<a id="example-mix-exs-file"></a>

#### Documentation

Documentation is automatically published to [hexdocs.pm](https://hexdocs.pm) when you publish your package. If you only want to publish the package itself you can run `mix hex.publish package`, similarly if you want to (re)publish the documentation of an existing package version you can run `mix hex.publish docs`.

Before publishing documentation, Hex will build the documentation by running the `mix docs` task to make sure it is up to date. The main documentation tool for Elixir, `ex_doc` provides this task so if you add it as a dependency you don't have to do anything else to get automatic documentation builds when you publish your package. Check out the [documentation for ex_doc](https://hexdocs.pm/ex_doc/readme.html) for information on how to configure your docs, we recommend building your docs locally with `mix docs` before publishing them to Hex. Finally also take a look at the [Elixir guide for writing documentation](https://hexdocs.pm/elixir/writing-documentation.html) for suggestions and best practices.

If want to use another documentation tool or do post-processing on the build from ex_doc you can alias the `docs` task, check the [task alias docs](https://hexdocs.pm/mix/Mix.html#module-aliases) for more information. Built documentation should be put in the `doc/` directory with at least an `index.html` file.

#### Example mix.exs file

```elixir
defmodule Postgrex.MixProject do
  use Mix.Project

  def project() do
    [
      app: :postgrex,
      version: "0.1.0",
      elixir: "~> 1.0",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "Postgrex",
      source_url: "https://github.com/elixir-ecto/postgrex"
    ]
  end

  def application() do
    []
  end

  defp deps() do
    [
      {:decimal, "~> 1.0"},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "A few sentences (a paragraph) describing the project."
  end

  defp package() do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "postgrex",
      # These are the default files included in the package
      files: ~w(lib priv .formatter.exs mix.exs README* readme* LICENSE*
                license* CHANGELOG* changelog* src),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/elixir-ecto/postgrex"}
    ]
  end
end
```

### Submitting the package

After the package metadata and dependencies have been added to `mix.exs`, we are ready to publish the package with the `mix hex.publish` command:

```nohighlight
$ mix hex.publish
Publishing postgrex v0.4.0
  Dependencies:
    decimal ~> 0.1.0
  Excluded dependencies (not part of the Hex package):
    ex_doc
  Included files:
    lib/postgrex
    lib/postgrex/binary_utils.ex
    lib/postgrex/connection.ex
    lib/postgrex/protocol.ex
    lib/postgrex/records.ex
    lib/postgrex/types.ex
    mix.exs
Proceed? [Yn] Y
Published postgrex v0.4.0
```

Congratulations, you've published your package! It will appear on the [hex.pm](https://hex.pm/) site and will be available to add as a dependency in other Mix projects.

Please test your package after publishing by adding it as dependency to a Mix project and fetching and compiling it. If there are any issues, you can publish the package again for up to one hour after first publication. A publication can also be reverted with `mix hex.publish --revert VERSION`.

When running the command to publish a package, Hex will create a tar file of all the files and directories listed in the `:files` property. When the tarball has been pushed to the Hex servers, it will be uploaded to a CDN for fast and reliable access for users. Hex will also recompile the registry file that all clients will update automatically when fetching dependencies.

### Publishing from CI

You can automate publishing packages from tools such as CI. You need a key with permissions to publish packages:

```nohighlight
$ mix hex.user key generate --key-name publish-ci --permission api:write
Username:
Account password:
Generating key...
f48ac236bca15c3271e077c15c5320c4
```

If you are publishing a package for your organization it is recommended to use a key for the organization instead of a personal key:

```nohighlight
$ mix hex.organization key acme generate --key-name publish-ci --permission api:write
Local password:
f48ac236bca15c3271e077c15c5320c4
```

Set the key in the `HEX_API_KEY` system environment variable. To publish the package without being prompted pass the `--yes` flag:

```nohighlight
$ HEX_API_KEY=f48ac236bca15c3271e077c15c5320c4 mix hex.publish --yes
```

*Note that care should be used when automating publishing because Hex can output important warnings or even recommendations on how to improve your package that will easily be missed when the process is automated. Also note that Hex is still pre 1.0 so breaking changes can happen between any releases and CI will usually install the latest version.*
