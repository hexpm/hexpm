## Private Hexdocs

<div class="subtitle"><time datetime="2018-08-09T00:00:00Z">August 9, 2018</time> · by Eric Meadows-Jönsson</div>

Today we are happy to announce the release of [Hexdocs](https://hexdocs.pm/) for private packages. All the private packages you have uploaded documentation for (the default when running `mix hex.publish`) are now available and browsable on Hexdocs.

> As always you can re-upload documentation by checking out an old version of your package and running `mix hex.publish docs`.

### How does it work?

Documentation for organizations will be available under a unique subdomain for each organization, for example: <https://acme.hexdocs.pm>. When you first visit the subdomain for your organization you will be redirected to <https://hex.pm> and asked to log in to verify you are a member of the organization, if you are already logged to hex.pm you will be redirected back immediately. After logging you in hex.pm will create a hidden key and pass the user secret for the key back to hexdocs which will store it encrypted in a cookie. When you visit hexdocs.pm the key will be verified against the hex.pm API to ensure you are still allowed to access the organization docs.

The public side of Hexdocs is an Amazon S3 bucket hosting the static files users upload as part of their package documentation, with [Fastly](https://www.fastly.com/) as CDN in front. To support the new authentication scheme for private documentation [a new service](https://github.com/hexpm/hexdocs) had to be built that is replacing the S3 bucket.

Previous services have been deployed on Heroku, Hexdocs is the first service we deploy on [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/). So far our experience with GCP and Kubernetes have been good and we plan to move all our services there. We are also using Terraform to orchestrate all infrastructure and we are planning more blog posts about how be built Hexdocs on GCP with Terraform.
