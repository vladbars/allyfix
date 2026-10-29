# Vokabeln

A small German vocabulary app: flash cards, word sets, progress.

It is the example app for Allyfix, which tests iOS apps with people who have different
disabilities and fixes what stops them. Vokabeln is written the way many React Native apps
are — a custom tab bar, icon fonts, cards stacked on top of each other — and has the
accessibility problems that come with that. Allyfix fixes them on a branch of their own.

## Run

```sh
npm install
npx expo run:ios
```

The first run builds Vokabeln as its own app, with its icon and splash screen, installs it in
the iOS Simulator and starts the dev server; edits reload at once. Later, `npx expo start`
is enough while the app stays installed.

## Credits

Illustrations and the app icon were made with Meta's Muse Image model. Fonts: Fraunces and
Inter (SIL Open Font License).

## License

MIT
