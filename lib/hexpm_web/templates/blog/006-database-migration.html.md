## Database migration

<div class="subtitle"><time datetime="2018-09-28T00:00:00Z">September 28, 2018</time> · by Eric Meadows-Jönsson</div>

We are changing hosting provider from Heroku to Google Cloud. All applications have already been moved to Google Kubernetes Engine, but we sill have to move the database for hex.pm itself.

During the move of the database we will have to put the [hex.pm](/) website and API into read-only mode. While in this mode you will still be able to fetch public and private packages and browse hexdocs. Any actions requiring database writes such as making changes in your dashboard or publishing a package will show an error page.

The move is planned for Sunday, 7th of October 8 AM UTC. We expect [hex.pm](/) to be in read-only mode for less than 15 minutes.
