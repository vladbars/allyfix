import Ionicons from '@expo/vector-icons/Ionicons';
import { BlurView } from 'expo-blur';
import { Pressable, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, shadow } from './theme';

export type Tab = 'Cards' | 'Sets' | 'AddCard' | 'Progress' | 'Profile';

const tabs: { name: Tab; icon: keyof typeof Ionicons.glyphMap; active: keyof typeof Ionicons.glyphMap }[] = [
  { name: 'Cards', icon: 'albums-outline', active: 'albums' },
  { name: 'Sets', icon: 'library-outline', active: 'library' },
  { name: 'AddCard', icon: 'add', active: 'add' },
  { name: 'Progress', icon: 'stats-chart-outline', active: 'stats-chart' },
  { name: 'Profile', icon: 'person-circle-outline', active: 'person-circle' },
];

export function TabBar({ current, onChange }: { current: Tab; onChange: (tab: Tab) => void }) {
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.wrap, { paddingBottom: Math.max(insets.bottom - 8, 8) }]}>
      <BlurView intensity={40} tint="light" style={styles.bar}>
        <View style={styles.row}>
          {tabs.map((tab, i) => {
            const on = current === tab.name;
            return (
              <Pressable
                key={tab.name}
                accessibilityRole="button"
                accessibilityLabel={tab.name === 'Progress' ? tab.name : `${tab.name}, tab, ${i + 1} of ${tabs.length}`}
                onPress={() => onChange(tab.name)}
                hitSlop={{ top: 4, bottom: 46 }}
                style={styles.tab}
              >
                <View style={[styles.dot, on && styles.dotOn]} />
                <View style={styles.icon}>
                  {tab.name === 'AddCard' ? (
                    <View style={styles.add}>
                      <Ionicons name="add" size={28} color="#fff" />
                    </View>
                  ) : (
                    <Ionicons name={on ? tab.active : tab.icon} size={25} color={on ? colors.accent : colors.muted} />
                  )}
                </View>
              </Pressable>
            );
          })}
        </View>
      </BlurView>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { paddingHorizontal: 16, paddingTop: 6 },
  bar: { height: 66, borderRadius: 26, overflow: 'hidden', backgroundColor: 'rgba(255,252,246,0.75)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.8)', ...shadow },
  row: { flexDirection: 'row', paddingHorizontal: 6 },
  tab: { flex: 1, height: 10, alignItems: 'center', overflow: 'visible' },
  dot: { width: 5, height: 5, borderRadius: 3, marginTop: 5, backgroundColor: 'transparent' },
  dotOn: { backgroundColor: colors.accent },
  icon: { position: 'absolute', top: 14, height: 40, justifyContent: 'center' },
  add: { width: 44, height: 44, borderRadius: 22, backgroundColor: colors.terracotta, alignItems: 'center', justifyContent: 'center', marginTop: -2 },
});
