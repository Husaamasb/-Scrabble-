import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const base = process.env.CAPACITOR_BUILD === 'true'
  ? './'
  : process.env.GITHUB_ACTIONS
    ? '/-Scrabble-/'
    : '/';

export default defineConfig({
  plugins: [react()],
  base,
});
