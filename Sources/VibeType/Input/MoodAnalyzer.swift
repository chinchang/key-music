import Foundation

/// Scores typed words against two hand-tuned lexicons (valence + arousal), both in [-1, +1].
/// Valence = pleasure/displeasure; arousal = energy/calmness.
/// Together they place the typed stream on Russell's circumplex so we can distinguish e.g.
/// romantic (high valence, low arousal) from happy (high valence, high arousal),
/// and depressed (low valence, low arousal) from angry (low valence, high arousal).
/// All text stays in RAM — never persisted.
final class MoodAnalyzer {
    private let valenceLexicon: [String: Double]
    private let arousalLexicon: [String: Double]
    private let queue = DispatchQueue(label: "keymusic.mood")
    private var currentWord = ""
    private var cachedValence: Double = 0
    private var cachedArousal: Double = 0
    private var recentWordMoods: [Mood] = [.neutral, .neutral, .neutral]
    private var cachedDominantMood: Mood = .neutral

    private let alpha: Double = 0.5            // EMA weight on the newest word (higher = snappier)
    private let moodWindowSize = 6
    private let moodDecay: Double = 0.6        // weight decay per age in the mood-vote window
    private let maxWordLength = 48

    init() {
        self.valenceLexicon = Self.buildValenceLexicon()
        self.arousalLexicon = Self.buildArousalLexicon()
    }

    func append(characters: String) {
        queue.async { [weak self] in
            guard let self else { return }
            for ch in characters {
                if ch.isLetter {
                    self.currentWord.append(ch)
                    if self.currentWord.count > self.maxWordLength {
                        self.currentWord.removeAll(keepingCapacity: true)
                    }
                } else {
                    self.flushLocked()
                }
            }
        }
    }

    var valence: Double { queue.sync { cachedValence } }
    var arousal: Double { queue.sync { cachedArousal } }
    /// The mood most supported by the recent few scored words, with exponential recency weights.
    /// Flips directly from one mood to another when 2+ opposing words land, skipping intermediates.
    var dominantMood: Mood { queue.sync { cachedDominantMood } }

    private func flushLocked() {
        guard !currentWord.isEmpty else { return }
        let w = currentWord.lowercased()
        currentWord.removeAll(keepingCapacity: true)

        let wv = valenceLexicon[w]
        let wa = arousalLexicon[w]
        guard wv != nil || wa != nil else { return }

        let v = wv ?? 0
        let a = wa ?? 0
        cachedValence = alpha * v + (1 - alpha) * cachedValence
        cachedArousal = alpha * a + (1 - alpha) * cachedArousal

        let wordMood = Mood.classify(valence: v, arousal: a)
        recentWordMoods.append(wordMood)
        if recentWordMoods.count > moodWindowSize {
            recentWordMoods.removeFirst()
        }
        cachedDominantMood = Self.weightedVote(moods: recentWordMoods, decay: moodDecay)
    }

    private static func weightedVote(moods: [Mood], decay: Double) -> Mood {
        guard !moods.isEmpty else { return .neutral }
        var scores: [Mood: Double] = [:]
        for (idx, m) in moods.reversed().enumerated() {
            scores[m, default: 0] += pow(decay, Double(idx))
        }
        return scores.max(by: { $0.value < $1.value })?.key ?? .neutral
    }

    private static func buildValenceLexicon() -> [String: Double] {
        let raw: [String: Int] = [
            // +5
            "love": 5, "amazing": 5, "wonderful": 5, "fantastic": 5, "brilliant": 5,
            "beautiful": 5, "perfect": 5, "awesome": 5, "ecstatic": 5, "paradise": 5,
            "magical": 5, "euphoric": 5, "blissful": 5, "exquisite": 5, "incredible": 5,
            "extraordinary": 5, "divine": 5, "breathtaking": 5, "adore": 5, "cherish": 5,
            // +4
            "joy": 4, "excellent": 4, "delighted": 4, "thrilled": 4, "fabulous": 4,
            "magnificent": 4, "gorgeous": 4, "stunning": 4, "radiant": 4, "heavenly": 4,
            "superb": 4, "splendid": 4, "marvelous": 4, "triumph": 4, "glorious": 4,
            "charming": 4, "elated": 4, "overjoyed": 4, "jubilant": 4, "inspired": 4,
            "darling": 4, "sweetheart": 4, "romance": 4, "intimate": 4, "tender": 4,
            // +3
            "happy": 3, "great": 3, "good": 3, "fun": 3, "smile": 3, "laugh": 3,
            "hope": 3, "bright": 3, "warm": 3, "cozy": 3, "lovely": 3, "sweet": 3,
            "calm": 3, "peaceful": 3, "glad": 3, "cheer": 3, "kind": 3, "celebrate": 3,
            "lucky": 3, "proud": 3, "hug": 3, "kiss": 3, "dance": 3, "sing": 3,
            "free": 3, "fresh": 3, "healthy": 3, "strong": 3, "safe": 3, "rich": 3,
            "smart": 3, "clever": 3, "cool": 3, "enjoy": 3, "success": 3, "win": 3,
            "wonder": 3, "sunshine": 3, "dream": 3, "smiling": 3, "passionate": 3,
            // +2
            "nice": 2, "like": 2, "gift": 2, "thank": 2, "thanks": 2, "welcome": 2,
            "play": 2, "easy": 2, "relaxed": 2, "pleasant": 2, "cheerful": 2,
            "rested": 2, "energetic": 2, "friend": 2, "help": 2, "share": 2,
            "please": 2, "bless": 2, "fair": 2, "better": 2, "pretty": 2,
            // +1
            "ok": 1, "okay": 1, "alright": 1, "clear": 1, "new": 1, "light": 1,
            "open": 1, "simple": 1, "soft": 1, "gentle": 1, "quiet": 1, "yes": 1,
            "sure": 1, "hi": 1, "hello": 1, "learn": 1, "grow": 1,
            // -1
            "meh": -1, "boring": -1, "slow": -1, "dull": -1, "miss": -1, "cold": -1,
            "empty": -1, "heavy": -1, "small": -1, "weak": -1, "hard": -1, "late": -1,
            "busy": -1, "difficult": -1, "tough": -1, "old": -1, "confused": -1,
            // -2
            "tired": -2, "gloomy": -2, "lonely": -2, "dreary": -2, "stuck": -2,
            "shame": -2, "dark": -2, "lost": -2, "alone": -2, "sorry": -2,
            "ignore": -2, "fail": -2, "regret": -2, "waste": -2, "grim": -2,
            "tense": -2, "nervous": -2, "bored": -2, "weary": -2, "numb": -2,
            // -3
            "sad": -3, "unhappy": -3, "angry": -3, "worried": -3, "afraid": -3,
            "scared": -3, "anxious": -3, "depressed": -3, "painful": -3, "annoying": -3,
            "mad": -3, "upset": -3, "fight": -3, "argue": -3, "trouble": -3,
            "problem": -3, "bitter": -3, "bleak": -3, "stress": -3, "sick": -3,
            "hurt": -3, "frustrated": -3, "pain": -3, "suffer": -3, "melancholy": -3,
            "somber": -3, "hollow": -3,
            // -4
            "bad": -4, "hate": -4, "wrong": -4, "broken": -4, "ugly": -4, "fear": -4,
            "cry": -4, "ruined": -4, "disgusted": -4, "furious": -4, "rage": -4,
            "abandoned": -4, "shattered": -4, "devastated": -4, "grief": -4,
            "crushing": -4, "exhausted": -4, "drained": -4,
            // -5
            "terrible": -5, "awful": -5, "horrible": -5, "disgusting": -5, "hateful": -5,
            "devastating": -5, "miserable": -5, "disaster": -5, "catastrophic": -5,
            "nightmare": -5, "agony": -5, "kill": -5, "die": -5, "dead": -5,
            "destroy": -5, "violence": -5, "attack": -5, "war": -5, "hell": -5,
            "suicide": -5, "murder": -5, "torture": -5, "despair": -5, "evil": -5,
            "cruel": -5, "hopeless": -5, "worthless": -5, "traumatic": -5, "bloody": -5,
            "fury": -5,
        ]
        var normalized: [String: Double] = [:]
        normalized.reserveCapacity(raw.count)
        for (k, v) in raw { normalized[k] = Double(v) / 5.0 }
        return normalized
    }

    private static func buildArousalLexicon() -> [String: Double] {
        let raw: [String: Int] = [
            // high arousal (+3…+5) — intense, energetic, aroused
            "rage": 5, "furious": 5, "fury": 5, "scream": 5, "explode": 5,
            "ecstatic": 5, "euphoric": 5, "frantic": 5, "panic": 5,
            "thrilled": 4, "amazing": 4, "fantastic": 4, "incredible": 4,
            "jubilant": 4, "extraordinary": 4, "attack": 4, "destroy": 4,
            "kill": 4, "murder": 4, "fight": 4, "angry": 4, "mad": 4,
            "war": 4, "crash": 4, "smash": 4, "burst": 4, "blast": 4,
            "excited": 4, "exhilarating": 4, "wild": 4, "crazy": 4,
            "violence": 4, "suicide": 4, "terror": 4, "shock": 4,
            "celebrate": 3, "dance": 3, "laugh": 3, "hype": 3, "rush": 3,
            "energetic": 3, "triumph": 3, "win": 3, "awesome": 3,
            "fabulous": 3, "stunning": 3, "magnificent": 3, "hateful": 3,
            "annoying": 3, "argue": 3, "stress": 3, "anxious": 3,
            "nervous": 3, "scared": 3, "afraid": 3, "worried": 3,

            // low arousal (-3…-5) — calm, quiet, subdued
            "peaceful": -5, "calm": -4, "quiet": -4, "gentle": -4, "soft": -4,
            "cozy": -4, "relaxed": -4, "serene": -5, "tranquil": -5,
            "hushed": -4, "still": -4, "whisper": -4, "tender": -4,
            "intimate": -4, "romance": -3, "darling": -3, "sweetheart": -3,
            "cherish": -3, "adore": -3, "warm": -2, "sweet": -2,
            "tired": -5, "sleepy": -5, "exhausted": -5, "drained": -5,
            "weary": -4, "sluggish": -4, "dull": -4, "bored": -4, "meh": -4,
            "sad": -3, "lonely": -4, "depressed": -5, "gloomy": -4,
            "miserable": -4, "dreary": -5, "bleak": -4, "somber": -4,
            "melancholy": -4, "melancholic": -4, "hollow": -4, "numb": -5,
            "vacant": -5, "resigned": -4, "empty": -4, "hopeless": -5,
            "worthless": -4, "despair": -4, "grief": -3, "mourning": -4,
        ]
        var normalized: [String: Double] = [:]
        normalized.reserveCapacity(raw.count)
        for (k, v) in raw { normalized[k] = Double(v) / 5.0 }
        return normalized
    }
}
