import path from 'path';
import TerserPlugin from 'terser-webpack-plugin';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default {
  optimization: {
    minimizer: [new TerserPlugin()],
  },
  entry: ["./js/app.js"],
  output: {
    filename: "app.js",
    path: path.resolve(__dirname, "../priv/static/assets"),
  },
  module: {
    rules: [
      {
        test: /\.js$/,
        exclude: /node_modules/,
        use: ["babel-loader"],
        resolve: {
          fullySpecified: false,
        },
      },
    ],
  },
  // Use source-map instead of default eval-based devtool for CSP compliance
  devtool: "source-map",
};
