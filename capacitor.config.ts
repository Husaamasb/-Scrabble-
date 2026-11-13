import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.husaamasb.scrabble',
  appName: 'Scrabble',
  webDir: 'dist',
  bundledWebRuntime: false,
  ios: {
    contentInset: 'automatic'
  },
  android: {
    allowMixedContent: false
  }
};

export default config;
