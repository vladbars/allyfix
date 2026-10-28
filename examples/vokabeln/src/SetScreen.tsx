import Ionicons from '@expo/vector-icons/Ionicons';
import * as Speech from 'expo-speech';
import { Alert, Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { articleColors, colors, fonts, shadow } from './theme';
import { Word, words, WordSet } from './words';

export function SetScreen({ set, onBack }: { set: WordSet; onBack: () => void }) {
  const sample = set.sample.map((id) => words.find((word) => word.id === id)).filter((word): word is Word => !!word);
  const left = set.words - set.seen;

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <View style={styles.hero}>
        <Image source={set.image} style={styles.art} />
        <Pressable style={styles.back} onPress={onBack}>
          <Ionicons name="chevron-back" size={22} color={colors.ink} />
        </Pressable>
      </View>

      <View style={styles.body}>
        <Text style={styles.levels}>{set.levels}</Text>
        <Text style={styles.title}>{set.title}</Text>
        <Text style={styles.description}>{set.description}</Text>

        {set.locked ? (
          <View style={styles.plus}>
            <Ionicons name="sparkles" size={18} color={colors.ochre} />
            <View style={styles.plusText}>
              <Text style={styles.plusTitle}>{set.words} words with Plus</Text>
              <Text style={styles.plusDetail}>Every set, offline cards and photo sets.</Text>
            </View>
            <Pressable style={styles.plusButton} onPress={() => Alert.alert('Vokabeln Plus', 'Coming soon')}>
              <Text style={styles.plusButtonText}>Try free</Text>
            </Pressable>
          </View>
        ) : (
          <>
            <View style={styles.stats}>
              <Stat value={set.seen} label="learned" />
              <Stat value={left} label="to go" />
              <Stat value={set.words} label="words" />
            </View>
            <View style={styles.track}>
              <View style={[styles.fill, { width: `${(set.seen / set.words) * 100}%` }]} />
            </View>
            <Pressable style={styles.study} onPress={() => Alert.alert(set.title, `Next ${Math.min(10, left)} words`)}>
              <Ionicons name="play" size={17} color={colors.card} />
              <Text style={styles.studyText}>Study {Math.min(10, left)} words</Text>
            </Pressable>
          </>
        )}

        {sample.length > 0 && (
          <>
            <Text style={styles.section}>In this set</Text>
            {sample.map((word) => (
              <WordRow key={word.id} word={word} />
            ))}
            <Text style={styles.more}>and {set.words - sample.length} more</Text>
          </>
        )}
      </View>
    </ScrollView>
  );
}

function Stat({ value, label }: { value: number; label: string }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

function WordRow({ word }: { word: Word }) {
  const say = () => Speech.speak(`${word.article} ${word.word}`, { language: 'de-DE', rate: 0.9 });
  return (
    <View style={styles.word}>
      <Image source={word.image} style={styles.thumb} />
      <View style={styles.wordText}>
        <Text style={styles.wordTitle}>
          <Text style={{ color: articleColors[word.article] }}>{word.article} </Text>
          {word.word}
        </Text>
        <Text style={styles.meaning}>{word.meaning}</Text>
      </View>
      <View style={styles.speak} onTouchEnd={say}>
        <Ionicons name="volume-medium-outline" size={20} color={colors.accent} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  content: { paddingBottom: 30 },
  hero: { height: 250 },
  art: { width: '100%', height: '100%' },
  back: { position: 'absolute', top: 12, left: 16, width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(255,252,246,0.92)', ...shadow },
  body: { marginTop: -28, borderTopLeftRadius: 28, borderTopRightRadius: 28, backgroundColor: colors.background, padding: 20, gap: 10 },
  levels: { fontFamily: fonts.bold, fontSize: 12, color: colors.terracotta, textTransform: 'uppercase', letterSpacing: 1 },
  title: { fontFamily: fonts.display, fontSize: 32, color: colors.ink },
  description: { fontFamily: fonts.text, fontSize: 15, lineHeight: 21, color: colors.muted },
  stats: { flexDirection: 'row', gap: 10, marginTop: 6 },
  stat: { flex: 1, paddingVertical: 12, borderRadius: 18, backgroundColor: colors.card, alignItems: 'center', ...shadow, shadowOpacity: 0.06 },
  statValue: { fontFamily: fonts.display, fontSize: 24, color: colors.ink },
  statLabel: { fontFamily: fonts.medium, fontSize: 12, color: colors.muted },
  track: { height: 6, borderRadius: 3, backgroundColor: colors.faint, overflow: 'hidden', marginTop: 4 },
  fill: { height: 6, borderRadius: 3, backgroundColor: colors.accent },
  study: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, height: 52, borderRadius: 26, backgroundColor: colors.accent, marginTop: 6 },
  studyText: { fontFamily: fonts.bold, fontSize: 16, color: colors.card },
  plus: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 14, borderRadius: 20, backgroundColor: '#F6E7CB', marginTop: 6 },
  plusText: { flex: 1, gap: 2 },
  plusTitle: { fontFamily: fonts.bold, fontSize: 15, color: colors.ink },
  plusDetail: { fontFamily: fonts.text, fontSize: 13, color: colors.muted },
  plusButton: { paddingHorizontal: 14, paddingVertical: 9, borderRadius: 16, backgroundColor: colors.ink },
  plusButtonText: { fontFamily: fonts.bold, fontSize: 13, color: colors.card },
  section: { fontFamily: fonts.displayMedium, fontSize: 20, color: colors.ink, marginTop: 14 },
  word: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 10, borderRadius: 18, backgroundColor: colors.card },
  thumb: { width: 54, height: 54, borderRadius: 12 },
  wordText: { flex: 1, gap: 2 },
  wordTitle: { fontFamily: fonts.display, fontSize: 18, color: colors.ink },
  meaning: { fontFamily: fonts.text, fontSize: 13, color: colors.muted },
  speak: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.accentSoft },
  more: { fontFamily: fonts.medium, fontSize: 13, color: colors.muted, textAlign: 'center', marginTop: 4 },
});
