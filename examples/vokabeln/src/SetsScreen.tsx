import Ionicons from '@expo/vector-icons/Ionicons';
import { useState } from 'react';
import { Alert, Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { colors, fonts, shadow } from './theme';
import { sets, WordSet } from './words';

export function SetsScreen() {
  const [mine, setMine] = useState(false);
  const [first, ...rest] = sets;
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <View style={styles.header}>
        <Text style={styles.title}>Sets</Text>
        <View style={styles.search} onTouchEnd={() => Alert.alert('Search', 'Coming soon')}>
          <Ionicons name="search" size={20} color={colors.ink} />
        </View>
        <Pressable style={styles.photo} onPress={() => Alert.alert('Set from a photo', 'Coming soon')}>
          <Ionicons name="camera-outline" size={17} color={colors.card} />
          <Text style={styles.photoText}>From a photo</Text>
        </Pressable>
      </View>

      <View style={styles.toggle}>
        <Pressable style={[styles.segment, !mine && styles.segmentOn]} onPress={() => setMine(false)}>
          <Text style={[styles.segmentText, !mine && styles.segmentTextOn]}>Topics</Text>
        </Pressable>
        <Text style={[styles.segment, styles.segmentText, mine && styles.segmentOn, mine && styles.segmentTextOn]} onPress={() => setMine(true)}>
          Mine
        </Text>
      </View>

      {mine ? (
        <Text style={styles.empty}>Sets you make from photos show up here.</Text>
      ) : (
        <>
          <Pressable style={styles.feature} onPress={() => Alert.alert(first.title)}>
            <Image source={first.image} style={styles.featureArt} />
            <View style={styles.featureText}>
              <Text style={styles.featureLabel}>Continue</Text>
              <Text style={styles.featureTitle}>{first.title}</Text>
              <Progress set={first} />
            </View>
          </Pressable>
          {rest.map((set) => (
            <SetRow key={set.id} set={set} />
          ))}
        </>
      )}
    </ScrollView>
  );
}

function Progress({ set }: { set: WordSet }) {
  return (
    <View style={styles.progressRow}>
      <View style={styles.track}>
        <View style={[styles.fill, { width: `${(set.seen / set.words) * 100}%` }]} />
      </View>
      <Text style={styles.progressText}>
        {set.seen}/{set.words}
      </Text>
    </View>
  );
}

function SetRow({ set }: { set: WordSet }) {
  return (
    <Pressable style={styles.row} onPress={() => Alert.alert(set.title)}>
      <Image source={set.image} style={styles.cover} />
      <View style={styles.rowText}>
        <Text style={styles.rowTitle}>{set.title}</Text>
        <Text style={styles.rowDescription} numberOfLines={2}>
          {set.description}
        </Text>
        <View style={styles.meta}>
          <Text style={styles.rowMeta}>
            {set.levels} · {set.words} words
          </Text>
          {set.locked && (
            <View style={styles.plus}>
              <Ionicons name="sparkles" size={11} color={colors.ochre} />
              <Text style={styles.plusText}>Plus</Text>
            </View>
          )}
        </View>
        {!set.locked && <Progress set={set} />}
      </View>
      <Pressable style={styles.more} onPress={() => Alert.alert(set.title, 'Rename, share or delete')}>
        <Ionicons name="ellipsis-vertical" size={18} color={colors.muted} />
      </Pressable>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  content: { padding: 18, gap: 14, paddingBottom: 30 },
  header: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 6 },
  title: { fontFamily: fonts.display, fontSize: 34, color: colors.ink, flex: 1 },
  search: { width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.card },
  photo: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 14, height: 38, borderRadius: 19, backgroundColor: colors.accent },
  photoText: { fontFamily: fonts.bold, fontSize: 14, color: colors.card },
  toggle: { flexDirection: 'row', gap: 8 },
  segment: { paddingHorizontal: 16, paddingVertical: 7, borderRadius: 16, borderWidth: 1, borderColor: colors.faint, backgroundColor: 'rgba(255,252,246,0.7)', overflow: 'hidden' },
  segmentOn: { backgroundColor: colors.ink, borderColor: colors.ink },
  segmentText: { fontFamily: fonts.medium, color: colors.muted, fontSize: 14 },
  segmentTextOn: { color: colors.card },
  feature: { borderRadius: 26, backgroundColor: colors.card, overflow: 'hidden', ...shadow },
  featureArt: { width: '100%', height: 190 },
  featureText: { padding: 16, gap: 4 },
  featureLabel: { fontFamily: fonts.bold, fontSize: 12, color: colors.terracotta, textTransform: 'uppercase', letterSpacing: 1 },
  featureTitle: { fontFamily: fonts.display, fontSize: 24, color: colors.ink },
  row: { flexDirection: 'row', alignItems: 'center', gap: 14, padding: 12, borderRadius: 22, backgroundColor: colors.card, ...shadow, shadowOpacity: 0.07 },
  cover: { width: 84, height: 84, borderRadius: 16 },
  rowText: { flex: 1, gap: 3 },
  rowTitle: { fontFamily: fonts.display, fontSize: 18, color: colors.ink },
  rowDescription: { fontFamily: fonts.text, fontSize: 13, lineHeight: 18, color: colors.muted },
  meta: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  rowMeta: { fontFamily: fonts.medium, fontSize: 12, color: colors.muted },
  plus: { flexDirection: 'row', alignItems: 'center', gap: 3, paddingHorizontal: 7, paddingVertical: 2, borderRadius: 8, backgroundColor: '#F6E7CB' },
  plusText: { fontFamily: fonts.bold, fontSize: 11, color: colors.ochre },
  progressRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 4 },
  track: { flex: 1, height: 5, borderRadius: 3, backgroundColor: colors.faint, overflow: 'hidden' },
  fill: { height: 5, borderRadius: 3, backgroundColor: colors.accent },
  progressText: { fontFamily: fonts.medium, fontSize: 11, color: colors.muted },
  more: { padding: 6 },
  empty: { fontFamily: fonts.text, color: colors.muted, textAlign: 'center', marginTop: 40 },
});
