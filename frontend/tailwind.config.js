/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      // Brand orange palette (warm, food-delivery energy).
      colors: {
        brand: {
          50: '#fff7ed',
          100: '#ffedd5',
          200: '#fed7aa',
          300: '#fdba74',
          400: '#fb923c',
          500: '#f97316',
          600: '#ea580c',
          700: '#c2410c',
          800: '#9a3412',
          900: '#7c2d12',
        },
      },
      fontFamily: {
        // Poppins for headings, Inter for body — loaded via index.html.
        sans: ['Inter', 'system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'sans-serif'],
        display: ['Poppins', 'Inter', 'system-ui', 'sans-serif'],
      },
      boxShadow: {
        soft: '0 2px 12px -2px rgba(0,0,0,0.06), 0 4px 24px -6px rgba(0,0,0,0.04)',
        card: '0 4px 20px -4px rgba(17,24,39,0.08), 0 8px 40px -12px rgba(17,24,39,0.06)',
        glow: '0 0 0 0 rgba(249,115,22,0.5)',
        lift: '0 12px 32px -8px rgba(234,88,12,0.25)',
      },
      borderRadius: {
        xl: '0.875rem',
        '2xl': '1.25rem',
        '3xl': '1.75rem',
      },
      keyframes: {
        'fade-in': {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        'slide-up': {
          '0%': { opacity: '0', transform: 'translateY(16px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-8px)' },
        },
        'pulse-ring': {
          '0%': { boxShadow: '0 0 0 0 rgba(249,115,22,0.55)' },
          '70%': { boxShadow: '0 0 0 12px rgba(249,115,22,0)' },
          '100%': { boxShadow: '0 0 0 0 rgba(249,115,22,0)' },
        },
        'bounce-subtle': {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-4px)' },
        },
      },
      animation: {
        'fade-in': 'fade-in 0.4s ease-out',
        'slide-up': 'slide-up 0.45s cubic-bezier(0.16,1,0.3,1)',
        shimmer: 'shimmer 1.6s linear infinite',
        float: 'float 4s ease-in-out infinite',
        'pulse-ring': 'pulse-ring 1.8s cubic-bezier(0.4,0,0.6,1) infinite',
        'bounce-subtle': 'bounce-subtle 0.6s ease-in-out',
      },
    },
  },
  plugins: [],
}
