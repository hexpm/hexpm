import path from 'path';
import MiniCssExtractPlugin from 'mini-css-extract-plugin';
import CssMinimizerPlugin from 'css-minimizer-webpack-plugin';
import TerserPlugin from 'terser-webpack-plugin';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default {
  optimization: {
    minimizer: [new TerserPlugin(), new CssMinimizerPlugin()],
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
      {
        test: /\.css$/,
        use: [MiniCssExtractPlugin.loader, "css-loader"],
      },
    ],
  },
  plugins: [
    new MiniCssExtractPlugin({ filename: "app.css" }),
  ],
  // Use source-map instead of default eval-based devtool for CSP compliance
  devtool: "source-map",
};
