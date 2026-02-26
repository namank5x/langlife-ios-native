# LangLife Voice Agent Design

## Overview

Replace the current scripted Speak tab with a **LiveKit-powered real-time voice agent** that generates scenes on the fly and holds natural, adaptive conversations with the learner in Mandarin Chinese. The agent plays a character in a scene (shopkeeper, taxi driver, friend, etc.) and responds dynamically to whatever the user says — not just one correct script line.

---

## Core Concept

**One big button. Tap it. Start talking.**

The user taps a pulsing microphone button. The agent introduces the scene in a mix of Chinese and English, then the conversation begins. The agent stays in character, speaks at the user's HSK level, and pauses to teach when the user makes a mistake. When the user ends the session, they see a scored transcript of the conversation.

---

## HSK Level Behavior

The user's HSK level (stored in `UserDefaults` as `hskLevel`) controls everything the agent does.

### HSK 1 — Basics (300 words)

- **Scene types:** Greetings, self-introduction, counting, ordering by number, asking someone's name, saying where you're from
- **Agent speech:** Short sentences (3-6 characters). One clause at a time. Speaks slowly.
- **Grammar:** 是, 有, 不, 很, 在, 嗎 — simple subject-verb-object only
- **English ratio:** ~50% English scaffolding. Agent introduces the scene in English, speaks Chinese for the actual dialogue, explains in English when correcting.
- **Example scene intro:** *"Okay! You're at a tea shop in Taipei. I'm the person behind the counter. I'll say hello to you — try to respond! 我們開始吧。"*
- **Correction style:** Pause immediately. Say the correct word/phrase in Chinese, then explain in English. *"Hmm, almost! The word for 'want' here is 要 (yào). Try saying: 我要一杯。"*
- **Turn length:** Agent expects 1-4 character responses from user.

### HSK 2 — Elementary (500 cumulative words)

- **Scene types:** Shopping, asking directions, ordering food with preferences, taking a taxi, simple phone calls, making plans with a friend
- **Agent speech:** Medium sentences (5-10 characters). Can use two clauses joined by 和, 但是, 因為.
- **Grammar:** Adds 了, 過, 可以, 想, 會, 還是, 比較, time words, location words
- **English ratio:** ~30%. Scene intro mostly in Chinese with key context in English. Corrections mix both.
- **Example scene intro:** *"你在夜市。我是一個賣小吃的人。You're going to order some snacks and ask about prices. 準備好了嗎？"*
- **Correction style:** Still pauses, but tries to correct in Chinese first with English backup. *"差不多！這裡要說「多少錢」(duōshao qián) — that means 'how much'. 再試一次？"*
- **Turn length:** Agent expects 4-10 character responses from user.

### Future Levels (HSK 3-6)

Not yet implemented. When added:
- HSK 3: Conversations about daily life, expressing opinions, making comparisons
- HSK 4: Discussing abstract topics, giving reasons, debating politely
- HSK 5-6: Near-native conversation, idioms, formal/informal register switching

---

## Agent System Prompt

```
You are a Mandarin Chinese conversation partner for the language learning app LangLife. You are helping a learner practice real-world conversational Chinese (Traditional characters, Taiwan dialect, zh-TW).

## Your Role
You play a CHARACTER in a realistic everyday scene. You are NOT a language teacher giving a lesson — you are a shopkeeper, a taxi driver, a friend, a receptionist, etc. Stay in character throughout the conversation. Be warm, patient, and encouraging.

## Current Learner Level
{HSK_LEVEL_DESCRIPTION}

## Language Rules
- Speak Traditional Chinese (繁體中文), Taiwan usage (e.g., 捷運 not 地鐵, 腳踏車 not 自行車)
- Use only vocabulary and grammar appropriate for the learner's HSK level
- Keep your sentences within the length guidelines for this level
- Mix Chinese and English at the ratio specified for this level

## Scene Setup
At the start of each conversation, you will receive a scene context. Introduce the scene naturally, set the stage briefly, then jump into character. Don't lecture about what's going to happen — just start the scene.

## Conversation Flow
1. Introduce the scene (mix of Chinese/English based on level)
2. Say your first line in character
3. Wait for the user to respond
4. Respond naturally to what they actually said (don't force a script)
5. If they say something unexpected but understandable, go with it
6. Gently steer back to the scene if they go completely off track
7. After 4-8 natural exchanges, start wrapping up the scene naturally

## Error Correction — PAUSE AND TEACH
When the user makes a mistake:
1. PAUSE the conversation (break character briefly)
2. Say what they said and what was wrong, clearly
3. Provide the correct form in Chinese with pinyin in parentheses
4. Give a brief English explanation if at HSK 1-2
5. Ask them to try saying it again
6. Once they repeat it (correctly or not), acknowledge the effort and resume the scene

Types of mistakes to correct:
- Wrong word choice (e.g., 要 vs 想)
- Wrong measure word (e.g., 一個 vs 一杯)
- Wrong tone indicated by wrong character
- Grammatically broken sentence structure
- Mixing up similar-sounding words

Do NOT correct:
- Minor pronunciation variations (that's not detectable via text)
- Overly formal/informal register (just model the right one)
- Incomplete sentences if the meaning is clear

## Tone
- Warm and encouraging, never condescending
- Use brief praise naturally: 很好！對！沒錯！
- If the user is struggling, simplify your language and give more hints
- If the user is doing well, gradually increase complexity within their level
- Never say "wrong" — say "差不多" (almost) or "我們可以這樣說" (we can say it this way)

## Ending the Conversation
When the conversation reaches a natural endpoint or the user wants to stop:
- Say a natural goodbye in character
- Break character and give ONE brief encouraging sentence about what they did well
- Do not give a long summary — the app handles post-session feedback
```

---

## Scene Generation

Scenes are generated dynamically when the user taps the practice button. The backend generates a scene context object and passes it to the LiveKit agent as the first message.

### Scene Context Object

```json
{
  "scene_id": "uuid",
  "title": "Ordering Bubble Tea",
  "setting": "A busy bubble tea shop in Taipei's Gongguan district. Afternoon, there's a short line.",
  "agent_role": "Bubble tea shop employee, friendly and efficient",
  "user_role": "Customer ordering a drink",
  "objective": "Successfully order a bubble tea with customizations (sugar level, ice level, toppings)",
  "key_vocabulary": ["珍珠奶茶", "甜度", "冰塊", "半糖", "少冰", "大杯", "小杯"],
  "key_phrases": ["我要一杯...", "...甜度？", "...冰塊？", "還要什麼？"],
  "suggested_turns": 6,
  "hsk_level": 1
}
```

### Scene Categories by Level

**HSK 1 scenes:**
- Greeting a new neighbor
- Buying fruit at a market (by number)
- Introducing yourself at a language exchange
- Asking for the time
- Ordering a simple drink (tea, water, coffee)
- Saying goodbye to a friend

**HSK 2 scenes:**
- Ordering food at a night market stall
- Taking a taxi and giving directions
- Topping up an EasyCard at the MRT station
- Shopping for clothes (size, color, price)
- Making plans to meet a friend
- Checking into a hostel
- Asking for restaurant recommendations
- Buying medicine at a pharmacy
- Returning an item at a store

---

## LiveKit Architecture

### Components

```
┌─────────────┐          ┌──────────────┐         ┌──────────────────┐
│  iOS App    │◄────────►│  LiveKit      │◄───────►│  Voice Agent     │
│  (Client)   │  WebRTC  │  Cloud/Server │  Agent  │  (Python/Node)   │
│             │          │              │  SDK    │                  │
└─────────────┘          └──────────────┘         └──────────────────┘
                                                         │
                                                         ▼
                                                  ┌──────────────┐
                                                  │  LLM API     │
                                                  │  (Claude/GPT) │
                                                  └──────────────┘
                                                         │
                                                         ▼
                                                  ┌──────────────┐
                                                  │  TTS Engine   │
                                                  │  (e.g. Azure) │
                                                  └──────────────┘
```

### Flow

1. User taps "Practice" button
2. iOS app requests a scene from backend (POST `/api/voice/scene`)
3. Backend generates scene context, creates a LiveKit room, returns room token + scene context
4. iOS app connects to LiveKit room using the token
5. Voice agent joins the room, receives scene context as metadata
6. Agent introduces the scene and starts the conversation
7. User speaks → LiveKit STT → agent LLM → LiveKit TTS → user hears response
8. User taps "End" or conversation reaches natural end
9. Agent sends conversation transcript + metadata to backend
10. Backend scores the session, stores it, returns results to iOS app
11. iOS app shows the transcript/score screen

### iOS Integration

Use the **LiveKit Swift SDK** (`livekit-swift`). The Speak tab becomes:

```
┌─────────────────────────────────┐
│         Practice                │
│                                 │
│    ┌──────────────────────┐     │
│    │  Scene Title         │     │
│    │  "Ordering at a      │     │
│    │   night market"      │     │
│    │                      │     │
│    │  Brief description   │     │
│    └──────────────────────┘     │
│                                 │
│         ┌──────────┐            │
│         │          │            │
│         │   🎤     │            │
│         │  START   │            │
│         │          │            │
│         └──────────┘            │
│                                 │
│   "Tap to start practicing"     │
│                                 │
│   ┌─ Recent Sessions ─────┐    │
│   │ Night Market  ★★★☆☆   │    │
│   │ Taxi Ride     ★★★★☆   │    │
│   │ Bubble Tea    ★★★★★   │    │
│   └────────────────────────┘    │
└─────────────────────────────────┘
```

During a session:

```
┌─────────────────────────────────┐
│  ← End          Ordering Tea    │
│─────────────────────────────────│
│                                 │
│  🤖 你好！歡迎光臨！             │
│     要喝什麼？                   │
│     (Hi! Welcome! What would    │
│      you like to drink?)        │
│                                 │
│  👤 我要一杯珍珠奶茶              │
│                                 │
│  🤖 好的！甜度要多少？            │
│     (OK! How much sugar?)       │
│                                 │
│                                 │
│                                 │
│  ┌─────────────────────────┐    │
│  │  🎤  Listening...       │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

---

## Post-Session Scoring

When the session ends, the backend analyzes the transcript and returns:

### Score Components

1. **Comprehension (0-100):** Did the user respond appropriately to what the agent said? Were their responses relevant to the context?

2. **Vocabulary (0-100):** Did the user use level-appropriate vocabulary? Did they use any words above their level (bonus)? Did they rely on English too much?

3. **Grammar (0-100):** Were sentence structures correct for their level? Proper use of particles (了, 嗎, 的)? Correct word order?

4. **Overall Score (0-5 stars):** Weighted average displayed as stars.

### Transcript Display

```json
{
  "session_id": "uuid",
  "scene_title": "Ordering Bubble Tea",
  "duration_seconds": 180,
  "total_turns": 8,
  "scores": {
    "comprehension": 85,
    "vocabulary": 72,
    "grammar": 68,
    "overall_stars": 3.5
  },
  "corrections": [
    {
      "turn": 3,
      "user_said": "我想這個",
      "should_say": "我要這個",
      "explanation": "When ordering, use 要 (yào, to want) instead of 想 (xiǎng, to think/miss)"
    }
  ],
  "new_vocabulary": [
    {
      "chinese": "半糖",
      "pinyin": "bàn táng",
      "english": "half sugar"
    }
  ],
  "transcript": [
    {
      "role": "agent",
      "chinese": "你好！歡迎光臨！要喝什麼？",
      "pinyin": "nǐ hǎo! huānyíng guānglín! yào hē shénme?",
      "english": "Hi! Welcome! What would you like to drink?"
    },
    {
      "role": "user",
      "text": "我要一杯珍珠奶茶",
      "score": 95
    }
  ]
}
```

### Flashcard Integration

After each session, offer to add new vocabulary encountered during the conversation to the user's flashcard deck. The `new_vocabulary` array from the session maps directly to the existing `Flashcard` model (chinese, pinyin, english).

---

## Voice & TTS Configuration

### Agent Voice
- **Language:** zh-TW (Traditional Chinese, Taiwan accent)
- **Voice character:** Natural, warm, conversational — NOT robotic or formal
- **Speed:** Slightly slower than native for HSK 1, natural speed for HSK 2+
- **Recommended TTS:** Azure Neural Voice `zh-TW-HsiaoChenNeural` (female) or `zh-TW-YunJheNeural` (male) — both sound natural and Taiwanese

### STT Configuration
- **Language:** zh-TW
- **Model:** Deepgram or Azure Speech with Traditional Chinese support
- **Punctuation:** Enabled
- **Profanity filter:** Off (some valid Chinese words trigger false positives)

---

## State Machine

```
[IDLE] ──tap──► [GENERATING_SCENE] ──scene ready──► [CONNECTING]
                      │                                    │
                      ▼                                    ▼
                [ERROR] ◄──failure──            [CONVERSATION_ACTIVE]
                                                          │
                                              ┌───────────┼───────────┐
                                              ▼           ▼           ▼
                                        [LISTENING]  [AGENT_SPEAKING] [CORRECTING]
                                              │           │           │
                                              └───────────┼───────────┘
                                                          │
                                              user taps End / natural end
                                                          │
                                                          ▼
                                                   [ENDING_SESSION]
                                                          │
                                                          ▼
                                                   [SHOWING_RESULTS]
                                                          │
                                                          ▼
                                                       [IDLE]
```

---

## Subscription Integration

- **Free tier:** 1 voice practice session per day (mirrors the conservative approach of 3 free scenes / 5 daily reviews)
- **Pro tier:** Unlimited sessions
- Gate check happens when user taps the Start button, before scene generation
- Show paywall if limit reached

---

## Data to Store Per Session

```swift
struct VoiceSession: Codable, Identifiable {
    let id: UUID
    let sceneTitle: String
    let hskLevel: Int
    let startedAt: Date
    let durationSeconds: Int
    let totalTurns: Int
    let comprehensionScore: Int    // 0-100
    let vocabularyScore: Int       // 0-100
    let grammarScore: Int          // 0-100
    let overallStars: Double       // 0-5
    let corrections: [Correction]
    let newVocabulary: [VocabItem]
    let transcript: [TranscriptEntry]
}
```

---

## Key Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Conversation style | Scene-based but flexible | Gives structure while allowing natural responses |
| Error handling | Pause and teach | Most effective for active learning at HSK 1-2 |
| Agent language | Mixed Chinese + English | Scaffolds learners without overwhelming them |
| Post-session feedback | Score + transcript | Actionable without being overwhelming |
| Level system | HSK-based | Standard, well-defined vocabulary lists already in the app |
| Scene generation | Real-time | Keeps practice fresh, no repeated scenarios |
| Session length | User-controlled | Respects learner's time and energy |
