import { DynamicColorIOS, Platform } from 'react-native';

/**
 * A color for the light look and one for the dark; iOS switches with the system. Typed as a
 * string because every color prop takes it, icons included, though the value is native.
 */
const both = (light: string, dark: string) => (Platform.OS === 'ios' ? (DynamicColorIOS({ light, dark }) as unknown as string) : light);

/**
 * Quiet and editorial in both looks: the photos carry the color. The main action is a pill of
 * ink on paper, or of paper on ink, and one warm metal marks what is precious.
 */
export const colors = {
  background: both('#F6F5F2', '#0E0E10'),
  card: both('#FFFFFF', '#1A1A1D'),
  paper: both('#EEEDEA', '#242428'),
  ink: both('#141416', '#F3F1EC'),
  muted: both('#6F6D69', '#8F8D88'),
  faint: both('#E3E1DC', '#2E2E33'),
  accent: both('#141416', '#F3F1EC'),
  onAccent: both('#FFFFFF', '#121214'),
  accentSoft: both('#ECEBE8', '#26262A'),
  signal: both('#A6762A', '#D9B26A'),
  highlight: both('#A6762A', '#D9B26A'),
  glass: both('rgba(255,255,255,0.82)', 'rgba(18,18,20,0.72)'),
  plusSoft: both('#F4EBD8', '#2A2519'),
  signalSoft: both('#F4EBD8', '#2A2519'),
};

/** der, die, das in the colors learners know them by, deep on paper and soft on ink. */
export const articleColors = {
  der: both('#2E5BC9', '#8FB4FF'),
  die: both('#C8433A', '#FF9C8F'),
  das: both('#2E8B57', '#86D9A8'),
};

export const fonts = {
  display: 'Fraunces_600SemiBold',
  displayMedium: 'Fraunces_500Medium',
  text: 'Inter_400Regular',
  medium: 'Inter_500Medium',
  bold: 'Inter_600SemiBold',
};

export const shadow = {
  shadowColor: '#000000',
  shadowOpacity: 0.08,
  shadowRadius: 18,
  shadowOffset: { width: 0, height: 8 },
};
