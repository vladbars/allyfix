# Accessibility: Vokabeln

Found by Allyfix on 30. October 2026 at 10:13: 9 screens, 56 problems (18 blocking), 0 tasks people could not do. The same findings, for tools, are in `findings.json` next to this file.

## How to work on this

- Start with **Tasks people could not do**: each is a real barrier, found by someone with that disability trying the task in the running app. Fix what stopped them.
- Each problem names the screen, how to get there from launch, and the element as VoiceOver reads it (`<icon>` is an icon-font glyph VoiceOver cannot read). Find that element in the code that draws the screen.
- Keep the look for everyone else, unless the problem is itself visual (a target too small, a state told only by color, text that does not fit at large sizes).
- Labels are short, say what the thing is or does, and are in the language of the app's own buttons, not of its content.
- To check a fix: in Allyfix, check the screen again, or test it with people; saved tests in `allyfix/tests` run again with no model (Allyfix → app → Run Saved Tests).

## Problems by screen

### Sets (Sets)

From launch: tap "Sets".

1. **The bottom tab bar icons have frames that miss the visible icons** — blocker, WCAG 1.3.2 Meaningful Sequence, 2.5.8 Target Size
   VoiceOver reads "Cards, tab, 1 of 5", "Sets, tab, 2 of 5", "AddCard, tab, 3 of 5", "Progress" and "Profile, tab, 5 of 5" with 15px-high frames at y=1147, far above the icons drawn in the bottom bar. The VoiceOver cursor and double-tap land there, not on the visible icons.
   - Button reading "Cards, tab, 1 of 5" at 23,782 72×11 pt
   - Button reading "Sets, tab, 2 of 5" at 94,782 72×11 pt
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Button reading "Progress" at 236,782 72×11 pt
2. **The search button is read as plain text** — blocker, WCAG 4.1.2 Name, Role, Value
   The magnifying-glass search button is read only as text "\uf55f". A VoiceOver user hears a meaningless symbol and cannot activate it as a button.
   - StaticText reading "<icon>" at 204,96 21×22 pt
   - Suggested label: "Search"
3. **The ⋮ menu buttons on the set cards have no label** — blocker, WCAG 1.1.1 Non-text Content
   VoiceOver reads the Weather, At work and Feelings cards with a trailing gap for the ⋮ menu, e.g. "Weather, Sun, rain, seasons and small talk about the sky, A1–A2 · 24 words, 9/24, \uf" . The visible three-dot menu has no label so it cannot be found or activated.
   - GenericElement reading "Weather, Sun, rain, seasons and small talk about the sky, A1–A2 · 24 words, 9/24, <icon>" at 17,494 367×125 pt
   - GenericElement reading "At work, Meetings, colleagues, email and the office, A2–B1 · 52 words, <icon>, Plus, <icon>" at 17,632 367×109 pt
   - GenericElement reading "Feelings, Saying how you are and understanding others, B1–B2 · 41 words, <icon>, Plus, <icon>" at 17,754 367×109 pt
   - Suggested label: "More options"
4. **3 targets smaller than 44×44 pt** — serious, WCAG 2.5.8 Target Size (Minimum), Apple HIG
   Apple recommends at least 44×44 points for anything to tap. Sizes: 140×38, 78×33, 67×33 pt.
   - GenericElement reading "<icon>, From a photo" at 243,87 141×39 pt
   - GenericElement reading "Topics" at 17,141 80×34 pt
   - Link reading "Mine" at 104,141 68×34 pt
5. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
6. **The Add tab is labeled "AddCard"** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads "AddCard, tab, 3 of 5" while the screen shows a + button. The run-together code name does not say what the tab does and Voice Control cannot match the visible "+".
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add"

### New card (Add card)

From launch: tap "AddCard".

1. **A button has no label** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver says only "button". Its label is an icon-font character, which VoiceOver cannot read. Someone who cannot see the screen does not know what it does.
   - GenericElement reading "<icon>" at 340,87 45×45 pt
2. **The card photo button has a code name label** — blocker, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads "img_add_header_v2" for the fox photo button. A person who cannot see the screen does not know it is a photo for the card that can be changed.
   - GenericElement reading "img_add_header_v2" at 17,147 367×191 pt
   - Suggested label: "Card image"
3. **The Level filter selection state is not announced** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver reads "A1", "A2", "B1", "B2" with no selected state, while A1 is drawn selected in white. A person cannot tell which level is currently chosen.
   - GenericElement reading "A1" at 17,559 87×45 pt
   - GenericElement reading "A2" at 111,559 87×45 pt
   - GenericElement reading "B1" at 204,559 87×45 pt
   - GenericElement reading "B2" at 298,559 86×45 pt
4. **The bottom tab bar buttons have wrong frames** — blocker, WCAG 1.3.2 Meaningful Sequence, 2.5.8 Target Size
   VoiceOver cursors for "Cards, tab, 1 of 5", "Sets, tab, 2 of 5", "AddCard, tab, 3 of 5", "Progress" and "Profile, tab, 5 of 5" are tiny 15px high strips that miss the drawn icons. The cursor and double-tap land in the wrong place.
   - Button reading "Cards, tab, 1 of 5" at 23,782 72×11 pt
   - Button reading "Sets, tab, 2 of 5" at 94,782 72×11 pt
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Button reading "Progress" at 236,782 72×11 pt
5. **5 targets smaller than 44×44 pt** — serious, WCAG 2.5.8 Target Size (Minimum), Apple HIG
   Apple recommends at least 44×44 points for anything to tap. Sizes: 44×44, 86×44, 85×44, 86×44… pt.
   - GenericElement reading "<icon>" at 340,87 45×45 pt
   - GenericElement reading "A1" at 17,559 87×45 pt
   - GenericElement reading "A2" at 111,559 87×45 pt
   - GenericElement reading "B1" at 204,559 87×45 pt
6. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
7. **The Add tab label runs words together** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads "AddCard, tab, 3 of 5" with words run together like a code name. It is confusing and hard to say for voice control.
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add card"

### Progress (Progress)

From launch: tap "Progress".

1. **Tab bar buttons have wrong frames** — blocker, WCAG 1.3.2 Meaningful Sequence, 2.5.8 Target Size
   VoiceOver cursors are 105x15 strips at y 1147, much smaller and shifted from the drawn icons. The cursor and double-tap land away from the visible tab buttons.
   - Button reading "Cards, tab, 1 of 5" at 23,782 72×11 pt
   - Button reading "Sets, tab, 2 of 5" at 94,782 72×11 pt
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Button reading "Progress" at 236,782 72×11 pt
2. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
3. **Streak flame icons are read as a symbol** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads each as "<icon>", a private-use symbol with no meaning. A blind user hears gibberish instead of the flame streak status shown in the circles.
   - StaticText reading "<icon>" at 43,431 15×16 pt
   - StaticText reading "<icon>" at 93,431 16×16 pt
   - StaticText reading "<icon>" at 143,431 15×16 pt
   - StaticText reading "<icon>" at 193,431 15×16 pt
4. **The Add tab label runs words together** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver says "AddCard, tab, 3 of 5" with words run together as a code name. It does not match a clear visible label for the + button.
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add card, tab, 3 of 5"
5. **VoiceOver reads 7 things that are not on screen** — serious, WCAG 1.3.2 Meaningful Sequence, 2.4.3 Focus Order
   It reads "Mo", "Tu", "We"… which nobody can see: content behind or outside what is shown. Swiping reaches it as if it were there.
   - StaticText reading "Mo" at 39,802 19×15 pt
   - StaticText reading "Tu" at 92,801 15×16 pt
   - StaticText reading "We" at 141,802 19×15 pt
   - StaticText reading "Th" at 193,802 16×15 pt

### Profile (Profile)

From launch: tap "Profile".

1. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
2. **The Language row is announced in German** — serious, WCAG 3.1.2 Language of Parts
   VoiceOver reads "Sprache, English" while the screen shows "Language". A Voice Control user cannot say what they see and the mixed language is confusing.
   - GenericElement reading "Sprache, English" at 17,295 367×59 pt
   - Suggested label: "Language, English"
3. **The Add tab has a code-name label** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads "AddCard, tab, 3 of 5" for the central plus button. The run-together code name does not say what the button does.
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add"
4. **The selected Profile tab is not announced as selected** — serious, WCAG 4.1.2 Name, Role, Value
   VoiceOver reads "Profile, tab, 5 of 5" with no selected state, while the tab bar shows Profile as selected with a filled icon and dot. A VoiceOver user cannot tell which tab is active.
   - Button reading "Profile, tab, 5 of 5" at 307,782 72×11 pt

### Getting around (Sets)

From launch: tap "Sets", then tap "CONTINUE".

1. **A button has no label** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver says only "button". Its label is an icon-font character, which VoiceOver cannot read. Someone who cannot see the screen does not know what it does.
   - GenericElement reading "<icon>" at 15,73 41×41 pt
2. **Speaker buttons are read as plain text** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver reads them as text "憚", not as buttons, so a blind user hears a symbol and cannot double-tap to play the pronunciation.
   - StaticText reading "<icon>" at 343,657 22×21 pt
   - StaticText reading "<icon>" at 343,741 22×21 pt
3. **Tab bar frames miss the visible icons** — blocker, WCAG 1.3.2 Meaningful Sequence, 2.5.8 Target Size
   VoiceOver frames are flat strips at y 1147 with height 15, much smaller and above the drawn tab icons, so the focus cursor and double-tap land in the wrong place.
   - Button reading "Cards, tab, 1 of 5" at 23,782 72×11 pt
   - Button reading "Sets, tab, 2 of 5" at 94,782 72×11 pt
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Button reading "Progress" at 236,782 72×11 pt
4. **A target smaller than 44×44 pt** — serious, WCAG 2.5.8 Target Size (Minimum), Apple HIG
   Apple recommends at least 44×44 points for anything to tap. Sizes: 40×40 pt.
   - GenericElement reading "<icon>" at 15,73 41×41 pt
5. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
6. **The Add tab label runs together as "AddCard"** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver says "AddCard, tab, 3 of 5" with words run together like a code name, which is confusing and does not match any visible text for Voice Control.
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add card"
7. **VoiceOver reads 7 things that are not on screen** — serious, WCAG 1.3.2 Meaningful Sequence, 2.4.3 Focus Order
   It reads "das Fahrrad", "the bicycle", "die Bäckerei"… which nobody can see: content behind or outside what is shown. Swiping reaches it as if it were there.
   - StaticText reading "das Fahrrad" at 95,815 229×23 pt
   - StaticText reading "<icon>" at 343,825 22×21 pt
   - StaticText reading "the bicycle" at 95,839 229×17 pt
   - StaticText reading "die Bäckerei" at 95,899 229×23 pt

### Weather (Sets)

From launch: tap "Sets", then tap "Weather".

1. **A button has no label** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver says only "button". Its label is an icon-font character, which VoiceOver cannot read. Someone who cannot see the screen does not know what it does.
   - GenericElement reading "<icon>" at 15,73 41×41 pt
2. **Pronunciation buttons read as plain text** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver reads the speaker icons as text "Ὑa" instead of a button, so a person who cannot see the screen cannot find or activate audio pronunciation.
   - StaticText reading "<icon>" at 343,657 22×21 pt
   - StaticText reading "<icon>" at 343,741 22×21 pt
   - Suggested label: "Play audio"
3. **Tab bar VoiceOver frames miss the icons** — blocker, WCAG 1.3.2 Meaningful Sequence, 2.5.8 Target Size
   VoiceOver frames for the five tab bar buttons are 105x15 strips above the icons, so the cursor and double-tap land in the wrong place.
   - Button reading "Cards, tab, 1 of 5" at 23,782 72×11 pt
   - Button reading "Sets, tab, 2 of 5" at 94,782 72×11 pt
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Button reading "Progress" at 236,782 72×11 pt
4. **A target smaller than 44×44 pt** — serious, WCAG 2.5.8 Target Size (Minimum), Apple HIG
   Apple recommends at least 44×44 points for anything to tap. Sizes: 40×40 pt.
   - GenericElement reading "<icon>" at 15,73 41×41 pt
5. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
6. **The Add tab label runs together as AddCard** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver says "AddCard, tab, 3 of 5" while no text is shown and the words run together, so it is confusing and a Voice Control user cannot say it.
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add Card"
7. **VoiceOver reads 7 things that are not on screen** — serious, WCAG 1.3.2 Meaningful Sequence, 2.4.3 Focus Order
   It reads "der Leuchtturm", "the lighthouse", "die Gießkanne"… which nobody can see: content behind or outside what is shown. Swiping reaches it as if it were there.
   - StaticText reading "der Leuchtturm" at 95,815 229×23 pt
   - StaticText reading "<icon>" at 343,825 22×21 pt
   - StaticText reading "the lighthouse" at 95,839 229×17 pt
   - StaticText reading "die Gießkanne" at 95,899 229×23 pt

### At work (Sets)

From launch: tap "Sets", then tap "At work".

1. **A button has no label** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver says only "button". Its label is an icon-font character, which VoiceOver cannot read. Someone who cannot see the screen does not know what it does.
   - GenericElement reading "<icon>" at 15,73 41×41 pt
2. **2 targets smaller than 44×44 pt** — serious, WCAG 2.5.8 Target Size (Minimum), Apple HIG
   Apple recommends at least 44×44 points for anything to tap. Sizes: 40×40, 78×34 pt.
   - GenericElement reading "<icon>" at 15,73 41×41 pt
   - GenericElement reading "Try free" at 290,438 79×35 pt
3. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
4. **The sparkle image in the Plus banner is exposed** — serious, WCAG 1.1.1 Non-text Content
   VoiceOver reads "<icon>" as a separate text item next to "52 words with Plus". The sparkle image is purely decorative and adds extra noise for someone who cannot see the screen.
   - StaticText reading "<icon>" at 34,446 19×19 pt
5. **The lock icons are read as a symbol** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads "<icon>" for each lock status icon. A symbol is read literally so a VoiceOver user cannot understand that the words are locked.
   - StaticText reading "<icon>" at 355,582 17×18 pt
   - StaticText reading "<icon>" at 355,666 17×18 pt
   - StaticText reading "<icon>" at 355,750 17×18 pt
   - Suggested label: "Locked"
6. **The Add tab label is a code name** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver says "AddCard, tab, 3 of 5" for the center + button. The code name with words run together does not say what the thing is and cannot be activated by voice with the visible name.
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add"
7. **VoiceOver reads 5 things that are not on screen** — serious, WCAG 1.3.2 Meaningful Sequence, 2.4.3 Focus Order
   It reads "die", "die Frist", "the deadline"… which nobody can see: content behind or outside what is shown. Swiping reaches it as if it were there.
   - StaticText reading "die" at 43,831 28×24 pt
   - StaticText reading "die Frist" at 95,823 249×23 pt
   - StaticText reading "<icon>" at 355,834 17×18 pt
   - StaticText reading "the deadline" at 95,847 249×17 pt

### Feelings (Sets)

From launch: tap "Sets", then tap "Feelings".

1. **A button has no label** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver says only "button". Its label is an icon-font character, which VoiceOver cannot read. Someone who cannot see the screen does not know what it does.
   - GenericElement reading "<icon>" at 15,73 41×41 pt
2. **2 targets smaller than 44×44 pt** — serious, WCAG 2.5.8 Target Size (Minimum), Apple HIG
   Apple recommends at least 44×44 points for anything to tap. Sizes: 40×40, 78×34 pt.
   - GenericElement reading "<icon>" at 15,73 41×41 pt
   - GenericElement reading "Try free" at 290,438 79×35 pt
3. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
4. **The sparkles icon is exposed to VoiceOver** — serious, WCAG 1.1.1 Non-text Content
   VoiceOver stops on "<icon>" for the sparkles icon next to "41 words with Plus". It adds no information and is confusing to hear.
   - StaticText reading "<icon>" at 34,446 19×19 pt
5. **The lock icons are read as a symbol** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads the lock icons as "<icon>". A person who cannot see the screen hears a symbol with no meaning and does not know the words are locked.
   - StaticText reading "<icon>" at 355,582 17×18 pt
   - StaticText reading "<icon>" at 355,666 17×18 pt
   - StaticText reading "<icon>" at 355,750 17×18 pt
   - Suggested label: "Locked"
6. **The Add tab label runs together as "AddCard"** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver says "AddCard, tab, 3 of 5" for the center + tab. The words run together and differ from what is drawn, so it is unclear and Voice Control cannot say it.
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add card"
7. **VoiceOver reads 5 things that are not on screen** — serious, WCAG 1.3.2 Meaningful Sequence, 2.4.3 Focus Order
   It reads "die", "die Gelassenheit", "the calm"… which nobody can see: content behind or outside what is shown. Swiping reaches it as if it were there.
   - StaticText reading "die" at 43,831 28×24 pt
   - StaticText reading "die Gelassenheit" at 95,823 249×23 pt
   - StaticText reading "<icon>" at 355,834 17×18 pt
   - StaticText reading "the calm" at 95,847 249×17 pt

### Today (Cards)

The app's first screen.

1. **The "All" filter looks like a selected button but is read as plain text** — blocker, WCAG 4.1.2 Name, Role, Value
   VoiceOver reads "All" as plain text, so a VoiceOver user cannot activate the filter and does not hear that it is selected.
   - StaticText reading "All" at 30,145 17×17 pt
2. **Tab bar frames miss the visible icons** — blocker, WCAG 1.3.2 Meaningful Sequence, 2.5.8 Target Size
   VoiceOver frames are only 105x15 and miss the visible tab icons, so the focus ring and double-tap land in the wrong place.
   - Button reading "Cards, tab, 1 of 5" at 23,782 72×11 pt
   - Button reading "Sets, tab, 2 of 5" at 94,782 72×11 pt
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Button reading "Progress" at 236,782 72×11 pt
3. **8 targets smaller than 44×44 pt** — serious, WCAG 2.5.8 Target Size (Minimum), Apple HIG
   Apple recommends at least 44×44 points for anything to tap. Sizes: 65×30, 40×30, 43×30, 40×30… pt.
   - GenericElement reading "Saved" at 66,138 65×31 pt
   - GenericElement reading "A1" at 136,138 41×31 pt
   - GenericElement reading "A2" at 183,138 44×31 pt
   - GenericElement reading "B1" at 232,138 41×31 pt
4. **"Progress" is not announced as a tab** — serious, WCAG 4.1.2 Name, Role, Value
   The other items in this bar are read as "tab, 1 of 5"; this one is read as a plain button, so the bar sounds broken.
   - Button reading "Progress" at 236,782 72×11 pt
5. **The flame streak icon is read as a symbol** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads the streak icon as "ﰓ", a symbol read literally, so a blind user does not know it means streak.
   - StaticText reading "<icon>" at 335,100 17×17 pt
   - Suggested label: "Streak"
6. **The Add tab is read as "AddCard"** — serious, WCAG 2.5.3 Label in Name, 4.1.2 Name, Role, Value
   VoiceOver reads "AddCard, tab, 3 of 5" with words run together, which is confusing and does not match the visible plus icon.
   - Button reading "AddCard, tab, 3 of 5" at 165,782 72×11 pt
   - Suggested label: "Add card"

## Saved tests

These pass today and must keep passing; each is a task a person with a disability can do since a fix.

- `allyfix/tests/mark-the-word-on-the-top-card-der-bahnhof-as-known.screenReader.json`
