# Package tarball

The package tarball contains the following files:

  * VERSION
    - The tarball version as a single ASCII integer
 
  * CHECKSUM
    - sha256 hex encoded checksum of tarball
    - `sha256(<<contents(VERSION)/binary, contents(metadata.config)/binary, contents(contents.tar.gz)/binary)`
 
  * metadata.config
    - Erlang term file
 
  * contents.tar.gz
    - Gzipped tarball with package contents
