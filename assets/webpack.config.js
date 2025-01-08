const path = require('path');
const webpack = require('webpack');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const CssMinimizerPlugin = require("css-minimizer-webpack-plugin");
const TerserPlugin = require("terser-webpack-plugin");

module.exports = (env, options) => ({
  optimization: {
    // minimize: true,
    minimizer: [
      new TerserPlugin(),
      new CssMinimizerPlugin(),
    ]
  },
  entry: ['./js/app.js', 'bootstrap/dist/css/bootstrap.css', './css/app.scss'],
  output: {
    filename: 'app.js',
    path: path.resolve(__dirname, '../priv/static/assets')
  },
  module: {
    rules: [
      {
        test: /\.js$/,
        exclude: /node_modules/,
        use: ['babel-loader']
      },
      {
        test: /\.scss$/,
        use: [
          MiniCssExtractPlugin.loader,
          {
            loader: "css-loader",
            options: {url: false}
          },
          "sass-loader"
        ]
      },
      {
          test: /\.css$/,
          use:  [MiniCssExtractPlugin.loader, 'css-loader']
      },
    ]
  },
  plugins: [
    new MiniCssExtractPlugin({ filename: 'app.css' }),
    new webpack.ProvidePlugin({
      jQuery: "jquery",
    })
  ]
});
