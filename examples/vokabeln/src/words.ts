import { ImageSourcePropType } from 'react-native';

export type Level = 'A1' | 'A2' | 'B1' | 'B2';

export type Word = {
  id: string;
  article: 'der' | 'die' | 'das';
  word: string;
  plural: string;
  meaning: string;
  level: Level;
  examples: string[];
  image: ImageSourcePropType;
};

export type WordSet = {
  id: string;
  title: string;
  description: string;
  levels: string;
  words: number;
  seen: number;
  locked: boolean;
  image: ImageSourcePropType;
};

export const words: Word[] = [
  {
    id: 'bahnhof',
    article: 'der',
    word: 'Bahnhof',
    plural: 'Bahnhöfe',
    meaning: 'the train station',
    level: 'A1',
    examples: ['Der Bahnhof ist gleich um die Ecke.', 'Wir treffen uns am Bahnhof.'],
    image: require('../assets/art/bahnhof.jpg'),
  },
  {
    id: 'bruecke',
    article: 'die',
    word: 'Brücke',
    plural: 'Brücken',
    meaning: 'the bridge',
    level: 'A2',
    examples: ['Die Brücke führt über den Fluss.', 'Wir gehen zu Fuß über die Brücke.'],
    image: require('../assets/art/bruecke.jpg'),
  },
  {
    id: 'fahrrad',
    article: 'das',
    word: 'Fahrrad',
    plural: 'Fahrräder',
    meaning: 'the bicycle',
    level: 'A1',
    examples: ['Ich fahre mit dem Fahrrad zur Arbeit.', 'Das Fahrrad hat einen Korb voller Blumen.'],
    image: require('../assets/art/fahrrad.jpg'),
  },
  {
    id: 'gewitter',
    article: 'das',
    word: 'Gewitter',
    plural: 'Gewitter',
    meaning: 'the thunderstorm',
    level: 'B1',
    examples: ['Am Abend kam ein starkes Gewitter.', 'Bei Gewitter bleiben wir zu Hause.'],
    image: require('../assets/art/gewitter.jpg'),
  },
  {
    id: 'baeckerei',
    article: 'die',
    word: 'Bäckerei',
    plural: 'Bäckereien',
    meaning: 'the bakery',
    level: 'A1',
    examples: ['Die Bäckerei öffnet um sechs Uhr.', 'Ich kaufe Brezeln in der Bäckerei.'],
    image: require('../assets/art/baeckerei.jpg'),
  },
  {
    id: 'leuchtturm',
    article: 'der',
    word: 'Leuchtturm',
    plural: 'Leuchttürme',
    meaning: 'the lighthouse',
    level: 'B2',
    examples: ['Der Leuchtturm steht auf einem Felsen.', 'Nachts leuchtet der Leuchtturm übers Meer.'],
    image: require('../assets/art/leuchtturm.jpg'),
  },
  {
    id: 'regenschirm',
    article: 'der',
    word: 'Regenschirm',
    plural: 'Regenschirme',
    meaning: 'the umbrella',
    level: 'A2',
    examples: ['Vergiss deinen Regenschirm nicht!', 'Der Regenschirm ist schon wieder kaputt.'],
    image: require('../assets/art/regenschirm.jpg'),
  },
  {
    id: 'giesskanne',
    article: 'die',
    word: 'Gießkanne',
    plural: 'Gießkannen',
    meaning: 'the watering can',
    level: 'B1',
    examples: ['Die Gießkanne steht auf dem Balkon.', 'Sie füllt die Gießkanne mit Regenwasser.'],
    image: require('../assets/art/giesskanne.jpg'),
  },
];

export const sets: WordSet[] = [
  { id: 'city', title: 'Getting around', description: 'Trams, tickets, streets and asking the way', levels: 'A1', words: 38, seen: 24, locked: false, image: require('../assets/art/set-city.jpg') },
  { id: 'weather', title: 'Weather', description: 'Sun, rain, seasons and small talk about the sky', levels: 'A1–A2', words: 24, seen: 9, locked: false, image: require('../assets/art/set-weather.jpg') },
  { id: 'work', title: 'At work', description: 'Meetings, colleagues, email and the office', levels: 'A2–B1', words: 52, seen: 0, locked: true, image: require('../assets/art/set-work.jpg') },
  { id: 'feelings', title: 'Feelings', description: 'Saying how you are and understanding others', levels: 'B1–B2', words: 41, seen: 0, locked: true, image: require('../assets/art/set-feelings.jpg') },
];

export const mascot = {
  reading: require('../assets/art/fox-reading.jpg'),
  waving: require('../assets/art/fox-wave.jpg'),
  writing: require('../assets/art/add-header.jpg'),
};
