module.exports = {
  content: [
    "../lib/**/*.{ex,heex}",
    "../lib/command_workbench_web/**/*.{ex,heex}",
  ],
  theme: {
    extend: {
      colors: {
        ink: {
          DEFAULT: "#1d1b16",
          900: "#1d1b16",
          700: "#2c2822",
          200: "#cfc6b8",
          50: "#f5f2ec",
        },
        sand: {
          50: "#fbf7f0",
          100: "#f4ecdf",
          200: "#eadfcd",
        },
        accent: {
          500: "#e07a5f",
          200: "#f4b5a4",
        },
      },
      fontFamily: {
        body: ["IBM Plex Sans", "sans-serif"],
        display: ["Space Grotesk", "sans-serif"],
      },
    },
  },
  plugins: [],
};
