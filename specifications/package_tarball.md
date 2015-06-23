# Package tarball

The package tarball contains the following files:

  * VERSION

    The tarball version as a single ASCII integer.

  * metadata.config

    Erlang term file, see [Package metadata](https://github.com/hexpm/hex_web/blob/master/specifications/package_metadata.md).

  * contents.tar.gz

    Gzipped tarball with package contents.

  * CHECKSUM

    sha256 hex-encoded checksum of the included tarball. The checksum is calculated by taking the contents of all files (except CHECKSUM), concatenating them, running sha256 over the concatenated data, and finally hex (base16) encoding it.

        contents = read_file("VERSION") + read_file("metadata.config") + read_file("content.tar.gz")
        checksum = sha256(contents)
        final_result = hex_encode(checksum)

