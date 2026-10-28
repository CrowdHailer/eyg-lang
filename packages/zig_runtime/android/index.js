import 'react-native-gesture-handler';
import { setErrorHandlerEnabled } from 'expo-app-metrics';
import { registerRootComponent } from 'expo';
import App from './App';
import { expoModules } from './src/modules';
import { initializeBackground } from './src/background-bootstrap';
// Metrics are opt-in EYG effects; importing the inventory must not capture errors.
setErrorHandlerEnabled(false);
initializeBackground(expoModules);
registerRootComponent(App);
