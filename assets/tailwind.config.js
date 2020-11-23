const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  purge: {
    enabled: process.env.NODE_ENV === 'production',
    content: [
      '../lib/hexpm_web/templates/**/*.html.eex',
      '../lib/hexpm_web/templates/**/*.html.md',
      '../lib/hexpm_web/views/**/*.ex'
    ]
  },
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
      },
    }
  },
  variants: {},
  plugins: []
}
