## Announcing new HexDocs search engine

<div class="subtitle"><time datetime="2025-10-27T00:00:00Z">27 October, 2025</time> · by Wojtek Mach</div>

Starting today, you can search across all Erlang and Elixir packages with [the new search engine and landing page for HexDocs](https://hexdocs.pm), powered by [Typesense](https://typesense.org).

![HexDocs homepage](/images/blog/019_hexdocs.png)

More importantly, you can scope your search to specific packages. For example, by running `mix hex.search` (remember to update Hex before with `mix local.hex`), Hex will open up HexDocs with the exact packages (and versions) used by your project preselected. For example, if you want to contribute to [Livebook](https://livebook.dev), running `mix hex.search` will [open up the following page](https://hexdocs.pm/?q=link&packages=aws_credentials%3A0.3.2%2Cbandit%3A1.6.8%2Cbypass%3A2.1.0%2Ccastore%3A1.0.15%2Ccc_precompiler%3A0.1.11%2Ccircular_buffer%3A1.0.0%2Ccowboy%3A2.13.0%2Ccowboy_telemetry%3A0.4.0%2Ccowlib%3A2.15.0%2Cdecimal%3A2.3.0%2Cdns_cluster%3A0.1.3%2Cearmark_parser%3A1.4.43%2Cecto%3A3.12.5%2Ceini_beam%3A2.2.4%2Celixir_make%3A0.9.0%2Cex_doc%3A0.37.3%2Cfile_system%3A1.1.1%2Cfinch%3A0.20.0%2Cfine%3A0.1.4%2Cfresh%3A0.4.4%2Chpax%3A1.0.3%2Ciso8601%3A1.3.4%2Cjason%3A1.4.4%2Cjose%3A1.11.10%2Cjsx%3A3.1.0%2Ckubereq%3A0.3.2%2Clazy_html%3A0.1.0%2Clogger_json%3A6.2.1%2Cmakeup%3A1.2.1%2Cmakeup_elixir%3A1.0.1%2Cmakeup_erlang%3A1.0.2%2Cmime%3A2.0.7%2Cmint%3A1.7.1%2Cmint_web_socket%3A1.0.4%2Cnimble_options%3A1.1.1%2Cnimble_parsec%3A1.4.2%2Cnimble_pool%3A1.1.0%2Cphoenix%3A1.8.0%2Cphoenix_ecto%3A4.6.3%2Cphoenix_html%3A4.2.1%2Cphoenix_live_dashboard%3A0.8.6%2Cphoenix_live_reload%3A1.6.1%2Cphoenix_live_view%3A1.1.11%2Cphoenix_pubsub%3A2.1.3%2Cphoenix_template%3A1.0.4%2Cplug%3A1.18.0%2Cplug_cowboy%3A2.7.4%2Cplug_crypto%3A2.1.0%2Cpluggable%3A1.1.0%2Cprotobuf%3A0.13.0%2Cpythonx%3A0.4.4%2Cranch%3A1.8.1%2Creq%3A0.5.8%2Ctelemetry%3A1.3.0%2Ctelemetry_metrics%3A1.1.0%2Ctelemetry_poller%3A1.1.0%2Cthousand_island%3A1.4.1%2Ctidewave%3A0.5.0%2Cwebsock%3A0.5.3%2Cwebsock_adapter%3A0.5.8%2Cyamerl%3A0.10.0%2Cyaml_elixir%3A2.11.0):

![Livebook Package Search](/images/blog/019_livebook.png)

This effectively gives developers a per-project documentation search experience, allowing them to quickly find relevant information. Tools like [Tidewave](https://github.com/tidewave-ai/tidewave_phoenix) also expose the search engine as a [MCP tool](https://modelcontextprotocol.io), allowing coding agents to search and explore all packages available to a given project.

A new version of Elixir's documentation generator, [ExDoc](https://github.com/elixir-lang/ex_doc/), has also been released with support for [custom search engines](https://hexdocs.pm/ex_doc/Mix.Tasks.Docs.html#module-search-engines). This way frameworks like [Phoenix](https://phoenixframework.org), which are effectively a collection of packages, can provide a custom search that includes `phoenix` itself, `phoenix_live_view`, `phoenix_html`, and other dependencies. This helps newcomers, who are not yet fully familar with the ecosystem, to find what they are looking for. Check out [the updated documentation for Phoenix](https://hexdocs.pm/phoenix/):

![Phoenix documentation](/images/blog/019_phoenix.png)

This release is a culmination of the efforts of several individuals and companies. We are grateful to [Typesense](https://typesense.org), for hosting our search engine and index, and [Plausible Analytics](https://plausible.io) for sponsoring development time. We also thank the bright minds of [Guillaume Hivert](https://github.com/ghivert), [Paulo Valim](https://github.com/paulo-valim), [Ruslan Doga](https://github.com/ruslandoga), and [José Valim](https://github.com/josevalim) for bringing the project to life.

## Implementation details

The search engine/index is a hosted Typesense instance. The HexDocs service, which does the job of unpacking and publishing documentation for each package, was augmented to [extract search metadata published by ExDoc and push it to Typesense](https://github.com/hexpm/hexdocs/pull/44). All packages published within the last year have been indexed. Documentation for existing projects can be republished at any time by running `mix deps.update ex_doc && mix hex.publish docs`. Pull requests to parse additional metadata formats are welcome (or you may alternatively publish the same metadata format as ExDoc).

While all Hex services are implemented primarily in Elixir, the new landing page talks directly to Typesense and therefore has no server-side component. For this reason, we kindly asked [Guillaume Hivert](https://github.com/ghivert) to implement the front-end in [Gleam](https://gleam.run), so we continue to leverage the overall Erlang Ecosystem. The project is using the [Lustre web framework](https://github.com/lustre-labs/lustre), and if you have suggestions or you want to add new features, [feel free to contribute to the project](https://github.com/hexpm/hexdocs-search).


