import Ionicons from '@expo/vector-icons/Ionicons';
import { LinearGradient } from 'expo-linear-gradient';
import { useState } from 'react';
import { Alert, Image, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { colors, fonts, shadow } from './theme';
import { mascot } from './words';

const levels = ['A1', 'A2', 'B1', 'B2'];

export function AddScreen() {
  const [word, setWord] = useState('');
  const [meaning, setMeaning] = useState('');
  const [level, setLevel] = useState('A1');
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <View style={styles.header}>
        <Text style={styles.title}>New card</Text>
        <Pressable style={styles.save} onPress={() => Alert.alert('Saved', `${word} – ${meaning}`)}>
          <Ionicons name="checkmark" size={24} color="#fff" />
        </Pressable>
      </View>
      <View style={styles.hero} accessible accessibilityLabel="img_add_header_v2">
        <Image source={mascot.writing} style={styles.heroArt} />
      </View>
      <Text style={styles.label}>German word</Text>
      <TextInput style={styles.input} placeholder="der Bahnhof" placeholderTextColor={colors.muted} value={word} onChangeText={setWord} />
      <Text style={styles.label}>Meaning</Text>
      <TextInput style={styles.input} placeholder="the train station" placeholderTextColor={colors.muted} value={meaning} onChangeText={setMeaning} />
      <Text style={styles.label}>Level</Text>
      <View style={styles.levels}>
        {levels.map((name) => (
          <Pressable key={name} style={[styles.level, level === name && styles.levelOn]} onPress={() => setLevel(name)}>
            <Text style={[styles.levelText, level === name && styles.levelTextOn]}>{name}</Text>
          </Pressable>
        ))}
      </View>
    </ScrollView>
  );
}

const week = [
  { day: 'Mo', cards: 12 },
  { day: 'Tu', cards: 8 },
  { day: 'We', cards: 15 },
  { day: 'Th', cards: 4 },
  { day: 'Fr', cards: 18 },
  { day: 'Sa', cards: 6 },
  { day: 'Su', cards: 11 },
];

export function ProgressScreen() {
  const most = Math.max(...week.map((day) => day.cards));
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <Text style={styles.title}>Progress</Text>
      <View style={styles.banner}>
        <Image source={mascot.reading} style={styles.bannerArt} />
        <View style={styles.bannerText}>
          <Text style={styles.bannerTitle}>12 days in a row</Text>
          <Text style={styles.bannerBody}>Fuchs is proud of you. Keep the streak going tomorrow.</Text>
          <View style={styles.streak}>
            {week.map((day, i) => (
              <View key={day.day} style={styles.streakDay}>
                <View style={[styles.streakDot, i === week.length - 1 && styles.streakToday]}>
                  <Ionicons name="flame" size={14} color={i === week.length - 1 ? '#fff' : colors.terracotta} />
                </View>
                <Text style={styles.day}>{day.day}</Text>
              </View>
            ))}
          </View>
        </View>
      </View>
      <View style={styles.stats}>
        <Stat value="214" label="words learned" />
        <Stat value="74" label="cards this week" />
        <Stat value="91%" label="remembered" />
      </View>
      <View style={styles.chart}>
        <Text style={styles.chartTitle}>This week</Text>
        <View style={styles.bars}>
          {week.map((day, i) => (
            <View key={day.day} style={styles.column}>
              <Text style={styles.barValue}>{day.cards}</Text>
              <LinearGradient
                colors={i === week.length - 1 ? [colors.terracotta, colors.ochre] : [colors.accent, '#7FA493']}
                style={[styles.bar, { height: 12 + (day.cards / most) * 110 }]}
              />
              <Text style={styles.day}>{day.day}</Text>
            </View>
          ))}
        </View>
      </View>
    </ScrollView>
  );
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

export function ProfileScreen() {
  const rows: { icon: keyof typeof Ionicons.glyphMap; title: string; value?: string; label?: string }[] = [
    { icon: 'language-outline', title: 'Language', value: 'English', label: 'Sprache, English' },
    { icon: 'sparkles-outline', title: 'Vokabeln Plus', value: 'All sets' },
    { icon: 'notifications-outline', title: 'Daily reminder', value: '8:00' },
    { icon: 'chatbubble-ellipses-outline', title: 'Write to us' },
    { icon: 'log-out-outline', title: 'Sign out' },
  ];
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.profile}>
        <Image source={mascot.waving} style={styles.avatar} />
        <Text style={styles.name}>Lena</Text>
        <Text style={styles.since}>Learning German since March</Text>
      </View>
      <View style={styles.list}>
        {rows.map((row, i) => (
          <Pressable key={row.title} style={[styles.row, i > 0 && styles.rowLine]} accessibilityLabel={row.label} onPress={() => Alert.alert(row.title)}>
            <View style={styles.rowIcon}>
              <Ionicons name={row.icon} size={19} color={colors.accent} />
            </View>
            <Text style={styles.rowTitle}>{row.title}</Text>
            {row.value && <Text style={styles.rowValue}>{row.value}</Text>}
            <Ionicons name="chevron-forward" size={17} color={colors.muted} />
          </Pressable>
        ))}
      </View>
      <Text style={styles.version}>Vokabeln 0.1</Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  content: { padding: 18, gap: 14, paddingBottom: 30 },
  header: { flexDirection: 'row', alignItems: 'center', marginTop: 6 },
  title: { fontFamily: fonts.display, fontSize: 34, color: colors.ink, flex: 1, marginTop: 6 },
  save: { width: 44, height: 44, borderRadius: 22, backgroundColor: colors.accent, alignItems: 'center', justifyContent: 'center', ...shadow },
  hero: { height: 190, borderRadius: 26, overflow: 'hidden', backgroundColor: colors.paper },
  heroArt: { width: '100%', height: '100%' },
  label: { fontFamily: fonts.bold, fontSize: 13, color: colors.muted, marginBottom: -6, marginLeft: 4 },
  input: { fontFamily: fonts.text, backgroundColor: colors.card, borderRadius: 18, paddingHorizontal: 16, height: 54, fontSize: 17, color: colors.ink, borderWidth: 1, borderColor: colors.faint },
  levels: { flexDirection: 'row', gap: 8 },
  level: { flex: 1, height: 44, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.card, borderWidth: 1, borderColor: colors.faint },
  levelOn: { backgroundColor: colors.ink, borderColor: colors.ink },
  levelText: { fontFamily: fonts.bold, color: colors.muted },
  levelTextOn: { color: colors.card },
  banner: { borderRadius: 26, backgroundColor: colors.card, overflow: 'hidden', ...shadow, shadowOpacity: 0.08 },
  bannerArt: { width: '100%', height: 180 },
  bannerText: { padding: 16, gap: 4 },
  streak: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 12 },
  streakDay: { alignItems: 'center', gap: 4 },
  streakDot: { width: 34, height: 34, borderRadius: 17, backgroundColor: '#F7E3D6', alignItems: 'center', justifyContent: 'center' },
  streakToday: { backgroundColor: colors.terracotta },
  bannerTitle: { fontFamily: fonts.display, fontSize: 21, color: colors.ink },
  bannerBody: { fontFamily: fonts.text, fontSize: 14, lineHeight: 19, color: colors.muted },
  stats: { flexDirection: 'row', gap: 10 },
  stat: { flex: 1, padding: 14, borderRadius: 20, backgroundColor: colors.card, ...shadow, shadowOpacity: 0.06 },
  statValue: { fontFamily: fonts.display, fontSize: 26, color: colors.ink },
  statLabel: { fontFamily: fonts.text, fontSize: 12, color: colors.muted },
  chart: { padding: 18, borderRadius: 26, backgroundColor: colors.card, ...shadow, shadowOpacity: 0.06 },
  chartTitle: { fontFamily: fonts.bold, fontSize: 15, color: colors.ink, marginBottom: 12 },
  bars: { flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between', height: 160 },
  column: { alignItems: 'center', gap: 6 },
  barValue: { fontFamily: fonts.medium, fontSize: 11, color: colors.muted },
  bar: { width: 26, borderRadius: 9 },
  day: { fontFamily: fonts.medium, fontSize: 12, color: colors.muted },
  profile: { alignItems: 'center', marginTop: 10 },
  avatar: { width: 130, height: 130, borderRadius: 65, borderWidth: 4, borderColor: colors.card },
  name: { fontFamily: fonts.display, fontSize: 28, color: colors.ink, marginTop: 10 },
  since: { fontFamily: fonts.text, fontSize: 14, color: colors.muted },
  list: { borderRadius: 24, backgroundColor: colors.card, overflow: 'hidden', ...shadow, shadowOpacity: 0.06 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, height: 58 },
  rowLine: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.faint },
  rowIcon: { width: 32, height: 32, borderRadius: 10, backgroundColor: colors.accentSoft, alignItems: 'center', justifyContent: 'center' },
  rowTitle: { fontFamily: fonts.medium, flex: 1, fontSize: 16, color: colors.ink },
  rowValue: { fontFamily: fonts.text, fontSize: 14, color: colors.muted },
  version: { fontFamily: fonts.text, textAlign: 'center', color: colors.muted, fontSize: 12 },
});
