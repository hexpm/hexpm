## Hex v2.0 released with new version solver

<div class="subtitle"><time datetime="2022-10-30T00:00:00Z">30 October, 2022</time> · by Eric Meadows-Jönsson</div>

Hex 2.0 drops support for Elixir 1.0-1.4. Hex 1.0 will continue to be maintained but will only receive security updates. For more details see the [release announcement for Hex 1.0](/blog/hex-v1.0-released-and-the-future-of-hex).

### New version solver

The biggest change in 2.0 is the introduction of our new version solver [hex_solver](https://github.com/hexpm/hex_solver). A version solver for a package manager needs to be able to find the latest versions of a set of compatible packages that do not violate the user specified version requirements of each package, it needs to finish in a reasonable amount of time, and if version solving failed it needs to display a clear message that explains why it failed.

The current solver algorithm has been around since work begun on Hex in early 2014. Many improvements have been made to it since its introduction such as performance improvements and better error messages but the underlying algorithm has essentially been the same. Lately issues have been cropping up where the solver seemingly freezes (actually it isn't freezing, just taking a very long to find a solution), the issue was becoming more and more common as the complexity and number of dependencies of Elixir projects have been growing along with the Hex registry becoming larger and larger.

Version solving can be generalized to the [boolean satisfiability problem](https://en.wikipedia.org/wiki/Boolean_satisfiability_problem) so the time complexity is NP-complete, this means no known algorithm can solve it quickly for larger input sets. [SAT solvers](https://en.wikipedia.org/wiki/SAT_solver) exists that can still solve for many inputs in a reasonable amount of time. The problem with SAT solver is that they are generalized and cannot use any optimizations for the specific problem domain of version solving, another issue is that there are usually many solutions that satisfy the version requirements but we expect the package manager to always the latest compatible versions. Finally SAT solvers cannot create an explanatory error message that explains why solving failed.

With this in mind we chose to base our new solver on [Natalie Weizenbaum's PubGrub](https://nex3.medium.com/pubgrub-2fb6470504f) which in turn is based on [Conflict-Driven Clause Learning ](https://en.wikipedia.org/wiki/Conflict-driven_clause_learning). PubGrub is used in the Dart programming language [package manager called pub](https://pub.dev).

When traditional version solvers encounter conflicting versions they simply backtrack to where the probable package introduced the conflicting version and try a different version. The problem with this approach is that it's hard to derive the underlying cause of the conflict and often the same combinations of package versions are tried multiple times even though they are known to be incompatible. PubGrub solves this by recording the root cause of the conflict and can then skip all package version combinations that caused it and avoid large portions of the search space. Recording the conflict causes has the added benefit that we can use them to create human readable error messages that step-by-step explain why solving failed if no solution can be found.

![solve failure](/images/blog/016_solve_failure.png)

### What's next?

We are planning to replace the current HTTP client in Hex that uses [httpc](https://www.erlang.org/doc/man/httpc.html) to one based on [Mint](https://github.com/elixir-mint/mint). Mint supports HTTP/2 so some performance improvements may be seen, but most importantly, with Mint we will have finer grained control of request timeouts. With httpc timeouts can only be set for the entire request, but with Mint the timeout can be based on last received data, this should give an out of the box better experience for users on slow or unreliable networks when fetching larger packages.

SSO login with initial support for Okta and Google is also on the roadmap. Along with that we will be adding web authentication for the CLI to support SSO and 2FA.

If you would like to contribute to any of these features or have other improvements you want to work on then you can find the Hex team in the #hex channel on the [Elixir slack](https://elixir-slackin.herokuapp.com/) or find us on GitHub at [github.com/hexpm/hexpm](https://github.com/hexpm/hexpm) or [github.com/hexpm/hex](https://github.com/hexpm/hex).
