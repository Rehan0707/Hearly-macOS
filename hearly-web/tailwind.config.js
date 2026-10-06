/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'brand-purple': '#C5A3FF',
      },
      fontFamily: {
        display: ['Google Sans Flex', 'sans-serif'],
        body: ['Google Sans Flex', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
