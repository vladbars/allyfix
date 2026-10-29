import { Fraunces_500Medium, Fraunces_600SemiBold } from '@expo-google-fonts/fraunces';
import { Inter_400Regular, Inter_500Medium, Inter_600SemiBold, useFonts } from '@expo-google-fonts/inter';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { CardsScreen } from './src/CardsScreen';
import { AddScreen, ProfileScreen, ProgressScreen } from './src/OtherScreens';
import { SetsScreen } from './src/SetsScreen';
import { Tab, TabBar } from './src/TabBar';
import { colors } from './src/theme';

SplashScreen.preventAutoHideAsync();
SplashScreen.setOptions({ fade: true, duration: 300 });

export default function App() {
  const [tab, setTab] = useState<Tab>('Cards');
  const [loaded] = useFonts({ Fraunces_500Medium, Fraunces_600SemiBold, Inter_400Regular, Inter_500Medium, Inter_600SemiBold });
  useEffect(() => {
    if (loaded) SplashScreen.hideAsync();
  }, [loaded]);
  if (!loaded) return <View style={styles.app} />;

  return (
    <SafeAreaProvider>
      <View style={styles.app}>
        <SafeAreaView style={styles.app} edges={['top']}>
          <View style={styles.content}>
            {tab === 'Cards' && <CardsScreen />}
            {tab === 'Sets' && <SetsScreen />}
            {tab === 'AddCard' && <AddScreen />}
            {tab === 'Progress' && <ProgressScreen />}
            {tab === 'Profile' && <ProfileScreen />}
          </View>
          <TabBar current={tab} onChange={setTab} />
        </SafeAreaView>
        <StatusBar style="auto" />
      </View>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  app: { flex: 1, backgroundColor: colors.background },
  content: { flex: 1 },
});
