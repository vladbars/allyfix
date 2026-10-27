import Ionicons from '@expo/vector-icons/Ionicons';
import * as Speech from 'expo-speech';
import { useEffect, useRef, useState } from 'react';
import { Animated, Easing, Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { articleColors, colors, fonts, shadow } from './theme';
import { Level, Word, words } from './words';

const filters = ['All', 'Saved', 'A1', 'A2', 'B1', 'B2'] as const;
type Filter = (typeof filters)[number];
const goal = 20;

export function CardsScreen() {
  const [filter, setFilter] = useState<Filter>('All');
  const [done, setDone] = useState(3);
  const [top, setTop] = useState(0);
  const deck = words.filter((word) => filter === 'All' || filter === 'Saved' || word.level === (filter as Level));
  const visible = deck.length ? [0, 1, 2].map((i) => deck[(top + i) % deck.length]) : [];

  const next = () => {
    setDone(Math.min(goal, done + 1));
    setTop(top + 1);
  };

  return (
    <View style={styles.screen}>
      <View style={styles.header}>
        <View>
          <Text style={styles.greeting}>Guten Morgen, Lena</Text>
          <Text style={styles.title}>Today</Text>
        </View>
        <View style={styles.streak}>
          <Ionicons name="flame" size={16} color={colors.terracotta} />
          <Text style={styles.streakText}>12</Text>
        </View>
      </View>

      <View style={styles.filters}>
        {filters.map((name) => {
          const selected = name === filter;
          return (
            <Pressable
              key={name}
              style={[styles.chip, selected && styles.chipOn]}
              onPress={() => setFilter(name)}
              accessibilityRole="button"
              accessibilityLabel={name}
              accessibilityState={{ selected }}
            >
              <Text style={[styles.chipText, selected && styles.chipTextOn]}>{name}</Text>
            </Pressable>
          );
        })}
      </View>

      <View style={styles.progress}>
        <View style={styles.track}>
          <View style={[styles.fill, { width: `${(done / goal) * 100}%` }]} />
        </View>
        <Text style={styles.count}>
          {done} of {goal}
        </Text>
      </View>

      <View style={styles.stack}>
        {visible
          .slice(1)
          .reverse()
          .map((word, i) => {
            const depth = 2 - i;
            return (
              <View key={`${word.id}-${depth}`} style={[styles.card, { transform: [{ translateY: depth * 24 }, { scale: 1 - depth * 0.04 }], opacity: 1 - depth * 0.12 }]}>
                <CardFace word={word} />
              </View>
            );
          })}
        {visible[0] && <TopCard key={`${visible[0].id}-${top}`} word={visible[0]} onAnswer={next} />}
      </View>
    </View>
  );
}

function TopCard({ word, onAnswer }: { word: Word; onAnswer: (knewIt: boolean) => void }) {
  const flip = useRef(new Animated.Value(0)).current;
  const exit = useRef(new Animated.Value(0)).current;
  const enter = useRef(new Animated.Value(0)).current;
  const [flipped, setFlipped] = useState(false);

  useEffect(() => {
    Animated.spring(enter, { toValue: 1, friction: 7, tension: 70, useNativeDriver: true }).start();
  }, [enter]);

  const turn = () => {
    Animated.spring(flip, { toValue: flipped ? 0 : 1, friction: 8, tension: 50, useNativeDriver: true }).start();
    setFlipped(!flipped);
  };

  const answer = (knewIt: boolean) => {
    Animated.timing(exit, { toValue: knewIt ? 1 : -1, duration: 340, easing: Easing.in(Easing.cubic), useNativeDriver: true }).start(() => onAnswer(knewIt));
  };

  const front = {
    opacity: flip.interpolate({ inputRange: [0, 0.5, 0.501, 1], outputRange: [1, 1, 0, 0] }),
    transform: [{ perspective: 1400 }, { rotateY: flip.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '180deg'] }) }],
  };
  const back = {
    opacity: flip.interpolate({ inputRange: [0, 0.5, 0.501, 1], outputRange: [0, 0, 1, 1] }),
    transform: [{ perspective: 1400 }, { rotateY: flip.interpolate({ inputRange: [0, 1], outputRange: ['180deg', '360deg'] }) }],
  };
  const motion = {
    transform: [
      { translateX: exit.interpolate({ inputRange: [-1, 1], outputRange: [-520, 520] }) },
      { rotate: exit.interpolate({ inputRange: [-1, 1], outputRange: ['-14deg', '14deg'] }) },
      { translateY: enter.interpolate({ inputRange: [0, 1], outputRange: [24, 0] }) },
      { scale: enter.interpolate({ inputRange: [0, 1], outputRange: [0.96, 1] }) },
    ],
  };

  return (
    <Animated.View style={[styles.card, motion]}>
      <Pressable style={styles.flex} onPress={turn}>
        <Animated.View style={[styles.side, front]}>
          <CardFace word={word} onFlip={turn} />
        </Animated.View>
        <Animated.View style={[styles.side, styles.backSide, back]}>
          <Image source={word.image} style={styles.backArt} />
          <Text style={styles.meaning}>{word.meaning}</Text>
          <Text style={styles.backWord}>
            {word.article} {word.word}
          </Text>
        </Animated.View>
        <View style={styles.answers}>
          <Pressable style={({ pressed }) => [styles.answer, styles.again, pressed && styles.pressed]} onPress={() => answer(false)}>
            <Text style={styles.answerText}>Learn again</Text>
          </Pressable>
          <Pressable style={({ pressed }) => [styles.answer, styles.know, pressed && styles.pressed]} onPress={() => answer(true)}>
            <Text style={styles.answerText}>I know it</Text>
          </Pressable>
        </View>
      </Pressable>
    </Animated.View>
  );
}

function CardFace({ word, onFlip }: { word: Word; onFlip?: () => void }) {
  const [saved, setSaved] = useState(false);
  const [quiz, setQuiz] = useState(false);
  const say = () => Speech.speak(`${word.article} ${word.word}`, { language: 'de-DE', rate: 0.9 });

  return (
    <View style={styles.face}>
      <View style={styles.artFrame}>
        <Image source={word.image} style={styles.art} />
        <Text style={styles.level}>{word.level}</Text>
        <Pressable onPress={() => setSaved(!saved)} style={styles.bookmark}>
          <Ionicons name={saved ? 'bookmark' : 'bookmark-outline'} size={20} color={saved ? colors.terracotta : colors.ink} />
        </Pressable>
      </View>
      <View style={styles.wordRow}>
        <Text style={[styles.article, { color: articleColors[word.article] }]}>{word.article}</Text>
        <Text style={styles.word}>{word.word}</Text>
      </View>
      <Text style={styles.plural}>Plural: die {word.plural}</Text>
      <View style={styles.examples}>
        {quiz ? (
          <View style={styles.hidden}>
            <Text style={styles.hiddenText}>Examples hidden — say one yourself.</Text>
          </View>
        ) : (
          word.examples.map((example) => (
            <Text key={example} style={styles.example}>
              {highlight(example, word.word)}
            </Text>
          ))
        )}
      </View>
      <View style={styles.tools}>
        <Pressable style={styles.tool} onPress={say}>
          <Ionicons name="volume-high-outline" size={22} color={colors.accent} />
        </Pressable>
        <Pressable style={styles.tool} onPress={onFlip}>
          <Ionicons name="sync-outline" size={22} color={colors.accent} />
        </Pressable>
        <Pressable style={[styles.tool, quiz && styles.toolOn]} accessibilityRole="switch" accessibilityState={{ checked: quiz }} onPress={() => setQuiz(!quiz)}>
          <Ionicons name={quiz ? 'eye-off-outline' : 'eye-outline'} size={22} color={quiz ? '#fff' : colors.accent} />
        </Pressable>
      </View>
    </View>
  );
}

function highlight(sentence: string, word: string) {
  return sentence.split(new RegExp(`(${word})`)).map((part, i) =>
    part === word ? (
      <Text key={i} style={styles.exampleWord}>
        {part}
      </Text>
    ) : (
      part
    ),
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, paddingHorizontal: 18 },
  flex: { flex: 1 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end', marginTop: 6 },
  greeting: { fontFamily: fonts.medium, fontSize: 14, color: colors.muted },
  title: { fontFamily: fonts.display, fontSize: 34, color: colors.ink, marginTop: -2 },
  streak: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 12, paddingVertical: 7, borderRadius: 16, backgroundColor: colors.card, ...shadow, shadowOpacity: 0.06 },
  streakText: { fontFamily: fonts.bold, fontSize: 15, color: colors.ink },
  filters: { flexDirection: 'row', gap: 6, marginTop: 14 },
  chip: { paddingHorizontal: 12, paddingVertical: 6, borderRadius: 15, backgroundColor: 'rgba(255,252,246,0.7)', borderWidth: 1, borderColor: colors.faint },
  chipOn: { backgroundColor: colors.ink, borderColor: colors.ink },
  chipText: { fontFamily: fonts.medium, fontSize: 13, color: colors.muted },
  chipTextOn: { color: colors.card },
  progress: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 14, marginBottom: 14 },
  track: { flex: 1, height: 6, borderRadius: 3, backgroundColor: colors.faint, overflow: 'hidden' },
  fill: { height: 6, borderRadius: 3, backgroundColor: colors.accent },
  count: { fontFamily: fonts.medium, fontSize: 12, color: colors.muted },
  stack: { flex: 1, marginBottom: 52 },
  card: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, borderRadius: 28, backgroundColor: colors.card, ...shadow },
  side: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backfaceVisibility: 'hidden' },
  backSide: { alignItems: 'center', justifyContent: 'center', padding: 24, paddingBottom: 110 },
  backArt: { width: 150, height: 150, borderRadius: 75, marginBottom: 22 },
  meaning: { fontFamily: fonts.display, fontSize: 34, color: colors.ink, textAlign: 'center' },
  backWord: { fontFamily: fonts.medium, fontSize: 16, color: colors.muted, marginTop: 8 },
  face: { flex: 1, padding: 14 },
  artFrame: { height: 200, borderRadius: 20, overflow: 'hidden', backgroundColor: colors.paper },
  art: { width: '100%', height: '100%', resizeMode: 'cover' },
  level: { position: 'absolute', top: 10, left: 10, fontFamily: fonts.bold, fontSize: 12, color: colors.accent, backgroundColor: 'rgba(255,252,246,0.9)', paddingHorizontal: 9, paddingVertical: 4, borderRadius: 10, overflow: 'hidden' },
  bookmark: { position: 'absolute', top: 8, right: 8, width: 34, height: 34, borderRadius: 17, backgroundColor: 'rgba(255,252,246,0.9)', alignItems: 'center', justifyContent: 'center' },
  wordRow: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'center', gap: 8, marginTop: 16 },
  article: { fontFamily: fonts.displayMedium, fontSize: 24 },
  word: { fontFamily: fonts.display, fontSize: 38, color: colors.ink },
  plural: { fontFamily: fonts.text, fontSize: 14, color: colors.muted, textAlign: 'center', marginTop: 2 },
  examples: { marginTop: 14, gap: 6, paddingHorizontal: 6 },
  example: { fontFamily: fonts.text, fontSize: 15, lineHeight: 21, color: colors.ink },
  exampleWord: { fontFamily: fonts.bold },
  hidden: { height: 48, borderRadius: 14, borderWidth: 1, borderStyle: 'dashed', borderColor: colors.faint, alignItems: 'center', justifyContent: 'center' },
  hiddenText: { fontFamily: fonts.medium, fontSize: 13, color: colors.muted },
  tools: { flexDirection: 'row', justifyContent: 'center', gap: 18, marginTop: 'auto', marginBottom: 74 },
  tool: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.accentSoft, alignItems: 'center', justifyContent: 'center' },
  toolOn: { backgroundColor: colors.accent },
  answers: { position: 'absolute', left: 14, right: 14, bottom: 14, flexDirection: 'row', gap: 10 },
  answer: { flex: 1, height: 52, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  pressed: { transform: [{ scale: 0.97 }], opacity: 0.9 },
  know: { backgroundColor: colors.accent },
  again: { backgroundColor: colors.terracotta },
  answerText: { fontFamily: fonts.bold, fontSize: 16, color: '#fff' },
});
