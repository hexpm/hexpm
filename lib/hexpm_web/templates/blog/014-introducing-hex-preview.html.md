## Introducing Hex Preview

<div class="subtitle"><time datetime="2021-01-25T00:00:00Z">25 January, 2021</time> · by Todd Resudek</div>

After months of development, I am proud to announce the launch of [preview.hex.pm](https://preview.hex.pm)! 

It is important to note that this was built on top of all the work that was put into [diff.hex.pm](https://diff.hex.pm). Preview relies on much of the code contributed to that project (thanks, in no small part, to [Johanna Larsson](https://github.com/joladev).)

### What does it do?

Hex Preview is an online tool for viewing the source files of a Hex package. By searching for the package name, and then selecting a version number, you will see all of the files contained in the release.

### Can't I already do this on Github?

No, not really. While it is likely the source code of a Github project is the same as the source code in a release, there is absolutely no guarantee that is the case.

It is important to consider any packages you bring into a project need to be vetted for security and quality just as you would vet the project code itself. A malicious actor could very well introduce a security flaw in a Hex release and then put different code on Github. If you are only using Github source to review packages you are making a mistake.

### How were people doing this before?

The only way to audit package code before now was to download the package tarball and review it locally. This is still a totally valid method, but I think Hex Preview will be much simpler.

### How can I trust Hex Preview?

Hex Preview is maintained by the Hex team, hosted on Hex servers, and using releases from the official Hex registry.

### Great. What's next?

Hopefully, users will contribute to [the project](https://github.com/hexpm/preview) to make it even better.
