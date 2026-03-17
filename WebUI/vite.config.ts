import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    tailwindcss(),
    react(),
  ],
  // Critical: file:// loading requires relative asset paths
  base: './',
  build: {
    outDir: '../Sources/LocalTube/Resources/WebUI',
    emptyOutDir: true,
  },
})
