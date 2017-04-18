## FAQ

### How should I name my packages?

Please follow these simple rules when choosing the name of the package you're publishing on Hex.

1. **Never use another package's namespace**. For example, the namespace of the plug library is `Plug.`: if your project extends plug, then its modules should be called `PlugExtension` instead of `Plug.Extension`.
2. **Prefix extension packages with the original package name**. If your package extends the functionality of the plug package, then its name should be something like `plug_extension`.
