# Allyfix

**Allyfix checks whether people with disabilities can get things done in an iOS app, fixes
what stops them, and checks again.**

Six synthetic people try your app in the iOS Simulator, each with only what they can
perceive: one hears VoiceOver and sees nothing, one sees the screen blurred with text at 235%,
one cannot tell red from green, one cannot hear, one taps a few points off, one knows no
app conventions. When
someone gets stuck, Muse Wonder changes the app's code on a git branch, and the same person
tries the same task again. What got them through is kept as a test that replays with no AI.

Allyfix is a fast first pass before testing with real people, not a replacement for it.

## How it works

1. **Explore App.** Allyfix walks the app running in the Simulator: every tab, then what each
   tab leads to. It reads each screen through the macOS accessibility interface, the way
   VoiceOver sees it, and checks it.
2. **Check.** Rules catch what the accessibility tree shows (no label, a wrong role, a frame
   that misses what is drawn, a target too small). Muse Spark compares the screenshot with what
   VoiceOver reads and catches the rest (a card read as one element, a state told only by
   color). SAM 3.1 finds everything drawn to be pressed, and the X-ray sets each thing against
   VoiceOver: reachable by its own name, buried inside something bigger, or missing.
3. **Test People.** Muse Spark works out the two main tasks of a screen, then plays each
   person, step by step, with only their perception. Someone without a disability goes first:
   a task even they cannot do is not counted. A judge model looks at the screen after every
   step and decides whether the task got done.
4. **Fix.** Muse Wonder reads the app's source and the failures, and answers with exact edits,
   committed on a new branch `allyfix/<screen>-<n>`. The app reloads, the screen is checked
   again, and the people who were stuck try again. The fix page shows the screens before and
   after with the changed places framed, who gets through now, and the diff. Keep Fix brings
   it into your branch; Undo Fix throws it away.
5. **Saved tests.** A task someone managed after a fix is stored in `allyfix/tests` in the
   app's repository: the way to the screen, the same taps and swipes, and what the
   accessibility tree must show at the end. Re-test replays every way and every test with no
   model; it can run on its own whenever the code changes. "Prove They Catch It" runs the tests
   on the code before the fix, where they must fail, and after it, where they must pass.

### The people

Chosen after EN 301 549 §4.2, the standard the European Accessibility Act points to. Named
only by access need and tool.

| § | Person | Gets | Acts |
|---|---|---|---|
| 4.2.1 | Screen reader user | What VoiceOver reads, in swipe order; no picture | Activates elements, as a double tap does |
| 4.2.2 | Low vision | The screen at the Simulator's text size 235%, blurred | Touches and swipes what can be made out |
| 4.2.3 | Color vision deficiency | The screenshot through a deuteranopia filter (Machado 2009) | Touches and swipes |
| 4.2.4 | Deaf or hard of hearing | The plain screenshot, and only that a sound played, not what | Touches and swipes |
| 4.2.7 | Limited dexterity | The plain screenshot | Real taps, off their aim by the same fixed tremor on every run |
| 4.2.10 | Cognitive and learning | The plain screenshot | Acts only on what the words on screen say |

The blur and the color filter are test conditions, not a claim about how any one person sees.
Allyfix listens to the Simulator's own audio, and no other app's, while a person acts. When the
app answers with a sound, the recording of that step goes to Muse Voice Transcribe, and the
words are kept with the step. A hearing person is told the words; the deaf person is told only
that something sounded, so what the app says only out loud, they do not get. macOS asks once
for permission to capture system audio.
When the low vision person gets stuck, Allyfix also searches the text size at which the task
stops working for someone who sees well, to tell a layout that breaks from things too small
to make out.

### What needs a model, and what does not

| Step | Model |
|---|---|
| Finding problems in a screenshot, the tasks of a screen, playing a person, judging a step | Muse Spark (`muse-spark-1.3`) |
| Finding what is drawn to be pressed, for the X-ray | SAM 3.1 (`sam-3.1`) |
| Writing down what the app says out loud | Muse Voice Transcribe (`muse-voice-transcribe-1.0`) |
| Writing a fix | Muse Wonder (`muse-wonder-1.0`) |
| Rules, the walk, Re-test, saved tests, before/after comparison, reports | none |

## Run it

Requirements: a Mac with macOS 15 or later, Xcode 26 with an iOS Simulator, Node.js 20 or
later, and a Meta Model API key.

```sh
git clone <this repository> && cd allyfix
echo 'MODEL_API_KEY=your-key' > .env

# The example app, in its own terminal: built, installed in the Simulator, and served.
cd examples/vokabeln && npm install && npx expo run:ios
```

Open `Allyfix.xcodeproj` in Xcode and run the Allyfix scheme. On first launch, allow
Accessibility access for Allyfix in System Settings → Privacy & Security; Allyfix reads and
presses the app in the Simulator through it and sees nothing else. For your own app, run it
in the Simulator as usual and point Allyfix at its source folder when you first fix.

Real taps and swipes need the Simulator window in front where it taps. When another app
covers it, Allyfix waits and asks you to bring it forward.

## A walk through Vokabeln

[`examples/vokabeln`](examples/vokabeln) is a small German vocabulary app in Expo and React
Native, written the way many apps are: a custom tab bar, icon fonts, cards stacked on top of
each other. It comes with the accessibility problems that brings.

1. **Explore App.** Allyfix finds nine screens, including each word set behind the Sets tab.
   The app page shows them as a tree, with one column per person.
2. Open **Today**. The X-ray shows 25 things drawn to be pressed, and VoiceOver reaches 5. Run
   **Test People**. Screen reader user: stuck at "Mark der Bahnhof as
   known", because the whole card is read as one element and "I know it" cannot be reached.
   Deaf: stuck at finding out how the word is pronounced, because the app only says it out loud.
   Low vision: stuck at saving a word, because the bookmark is a thin icon.
3. **Fix**. The fix page shows the steps, then before and after: for low vision, Muse Wonder
   turned the 34-point bookmark into a 48-point "Save" button that turns into a filled
   "Saved" one.
4. **Keep Fix**, then **Re-test Now**: every screen is reached again and the saved tests pass.
   Put the old bookmark back in the code, and the test fails.

## Reports

From an app's **Reports** tab:

- **For coding agents:** `allyfix/ACCESSIBILITY.md` and `allyfix/findings.json` in the app's
  repository: each problem with its screen, the way there from launch, what VoiceOver reads,
  and how to check a fix. Claude Code, Codex or a person can work from it.
- **For the law and buyers:** drafts of the accessibility information the German BFSG
  requires (§ 14 with Annex 3) and a conformance report in the VPAT 2.5 EU format against
  EN 301 549, as Markdown and PDF. Only what Allyfix examined is judged; everything else is
  marked Not Evaluated. They are drafts to review, not certificates.

## Limits

- Synthetic people find barriers fast and repeatably, but they are models. Their findings are
  meant to be confirmed with people who use assistive technology.
- Runs on iOS apps in the Simulator, not on devices yet. The people can't type into text fields
  yet, so tasks that need typing aren't tested. Hearing is modeled as none, so partial hearing
  loss isn't covered.
- The walk goes two levels deep and stops at twelve screens; it never presses anything that
  deletes, pays, sends, signs out or changes settings.
- Fixes are local git branches. Allyfix does not open pull requests.

## License

MIT. The example app has its own [README](examples/vokabeln/README.md) and license.
