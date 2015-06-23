# Endpoints

The Hex API has two endpoints: an HTTP API, which is used for all administrative tasks and to browse packages; and a CDN, which is read-only and used to deliver the registry and package tarballs.

### HTTP API

See [apiary.apib](https://github.com/hexpm/hex_web/blob/master/apiary.apib) file at the root of this repository.

### CDN

  * /registry.ets.gz - [Registry](https://github.com/hexpm/hex_web/blob/master/specifications/registry.md)
  * /tarballs/PACKAGE-VERSION.tar - [Package tarball](https://github.com/hexpm/hex_web/blob/master/specifications/package_tarball.md)

### Hex.pm endpoints

Hex.pm uses the following root endpoints:

  * HTTP API - https://hex.pm/api
  * CDN - https://s3.amazonaws.com/s3.hex.pm
