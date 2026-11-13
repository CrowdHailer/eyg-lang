module.exports = {
  expo: {
    name: 'EYG', slug: 'eyg-native', version: '0.1.0', orientation: 'default',
    android: {
      package: 'run.eyg.nativeapp',
      permissions: [
        'android.permission.INTERNET', 'android.permission.VIBRATE',
        'android.permission.ACCESS_NETWORK_STATE', 'android.permission.ACCESS_WIFI_STATE',
        'android.permission.CAMERA', 'android.permission.RECORD_AUDIO',
        'android.permission.ACCESS_COARSE_LOCATION', 'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.READ_CONTACTS', 'android.permission.WRITE_CONTACTS',
        'android.permission.READ_CALENDAR', 'android.permission.WRITE_CALENDAR',
        'android.permission.POST_NOTIFICATIONS', 'android.permission.ACTIVITY_RECOGNITION',
        'android.permission.USE_BIOMETRIC', 'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VIDEO', 'android.permission.READ_MEDIA_AUDIO',
      ],
    },
    plugins: [
      ['expo-build-properties', { android: { minSdkVersion: 26 } }],
      'expo-asset', 'expo-audio', 'expo-calendar', 'expo-camera', 'expo-contacts',
      'expo-file-system', 'expo-font', 'expo-image-picker', 'expo-local-authentication',
      'expo-location', 'expo-media-library', 'expo-notifications', 'expo-secure-store',
      'expo-sensors', 'expo-sqlite', 'expo-video', 'expo-background-task',
      'expo-splash-screen',
      ['expo-widgets', { enableAndroid: true, widgets: [{
        name: 'EygWidget', displayName: 'EYG', description: 'EYG query results',
        ios: null, android: { minWidth: 160, minHeight: 80, targetCellWidth: 2, targetCellHeight: 1 },
      }] }],
    ],
  },
};
