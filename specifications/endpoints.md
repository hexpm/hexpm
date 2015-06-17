# Endpoints

The Hex API has two endpoints; the HTTP API is used for all administrative tasks and to browse packages, the CDN is read-only and used to deliver the registry and package tarballs.

### HTTP API

See apiary.apib file at the root of this repository.

### CDN

  * /registry.ets.gz - registry
  * /tarballs/PACKAGE-VERSION.tar - package tarball

### Hex.pm endpoints

Hex.pm uses the following root endpoints:

  * HTTP API - https://hex.pm/api
  * CDN - https://s3.amazonaws.com/s3.hex.pm
