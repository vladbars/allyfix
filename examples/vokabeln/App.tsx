import { Fraunces_500Medium, Fraunces_600SemiBold } from '@expo-google-fonts/fraunces';
import { Inter_400Regular, Inter_500Medium, Inter_600SemiBold, useFonts } from '@expo-google-fonts/inter';
import { LinearGradient } from 'expo-linear-gradient';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { CardsScreen } from './src/CardsScreen';
import { AddScreen, ProfileScreen, ProgressScreen } from './src/OtherScreens';
import { SetsScreen } from './src/SetsScreen';
import { Tab, TabBar } from './src/TabBar';
import { colors } from './src/theme';

export default function App() {
  const [tab, setTab] = useState<Tab>('Cards');
  const [loaded] = useFonts({ Fraunces_500Medium, Fraunces_600SemiBold, Inter_400Regular, Inter_500Medium, Inter_600SemiBold });
  if (!loaded) return <View style={styles.app} />;

  return (
    <SafeAreaProvider>
      <LinearGradient colors={[colors.background, colors.backgroundDeep]} style={styles.app}>
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
        <StatusBar style="dark" />
      </LinearGradient>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  app: { flex: 1, backgroundColor: colors.background },
  content: { flex: 1 },
});
