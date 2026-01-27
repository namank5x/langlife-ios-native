import Foundation

enum DefaultSpeakContent {
    struct SceneContent {
        let scene: SpeakScene
        let outline: SpeakChatOutline
        let turns: [SpeakTurn]
    }

    static let sceneContents: [SceneContent] = [
        bubbleTea,
        nightMarket,
        mrtTopUp
    ]

    static var scenes: [SpeakScene] {
        sceneContents.map(\.scene)
    }

    static func content(for sceneId: UUID) -> SceneContent? {
        sceneContents.first { $0.scene.id == sceneId }
    }

    private static let bubbleTeaId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let nightMarketId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let mrtTopUpId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    private static let bubbleTea = SceneContent(
        scene: SpeakScene(
            id: bubbleTeaId,
            title: "Bubble Tea Order",
            description: "Order bubble tea with sweetness and ice levels at a Taiwan drink shop.",
            tags: ["food", "ordering", "drinks"],
            level: .beginner,
            createdAt: nil
        ),
        outline: SpeakChatOutline(
            sceneId: bubbleTeaId,
            turns: [
                SpeakTurnOutline(
                    step: 1,
                    speakFirst: .ai,
                    aiIntent: "Greet and ask what drink the customer wants.",
                    userIntent: "Order a bubble tea with size, sugar, and ice level.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 2,
                    speakFirst: .ai,
                    aiIntent: "Offer toppings like boba and confirm preferences.",
                    userIntent: "Add boba and tweak the ice level.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 3,
                    speakFirst: .ai,
                    aiIntent: "Ask for a name and payment method.",
                    userIntent: "Give a name and pay with EasyCard.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 4,
                    speakFirst: .ai,
                    aiIntent: "Share wait time and pickup spot.",
                    userIntent: "Acknowledge pickup and thank them.",
                    focusHint: nil
                )
            ],
            practiceTip: "Use measure words like yi bei and polite markers mafan/xie xie."
        ),
        turns: [
            SpeakTurn(
                step: 1,
                aiLine: SpeakLine(
                    chinese: "歡迎光臨，要點什麼飲料呢？",
                    pinyin: "huān yíng guāng lín, yào diǎn shén me yǐn liào ne?",
                    english: "Welcome! What drink would you like?",
                    gloss: [
                        SpeakGlossToken(chinese: "歡迎光臨", pinyin: "huān yíng guāng lín", english: "welcome", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "要", pinyin: "yào", english: "want to", isPunctuation: nil),
                        SpeakGlossToken(chinese: "點", pinyin: "diǎn", english: "order", isPunctuation: nil),
                        SpeakGlossToken(chinese: "什麼", pinyin: "shén me", english: "what", isPunctuation: nil),
                        SpeakGlossToken(chinese: "飲料", pinyin: "yǐn liào", english: "drink", isPunctuation: nil),
                        SpeakGlossToken(chinese: "呢", pinyin: "ne", english: "particle", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "我要一杯中杯珍珠奶茶，半糖少冰。",
                    pinyin: "wǒ yào yī bēi zhōng bēi zhēn zhū nǎi chá, bàn táng shǎo bīng.",
                    english: "I’d like a medium bubble tea, half sugar, less ice.",
                    gloss: [
                        SpeakGlossToken(chinese: "我", pinyin: "wǒ", english: "I", isPunctuation: nil),
                        SpeakGlossToken(chinese: "要", pinyin: "yào", english: "want", isPunctuation: nil),
                        SpeakGlossToken(chinese: "一杯", pinyin: "yī bēi", english: "one cup", isPunctuation: nil),
                        SpeakGlossToken(chinese: "中杯", pinyin: "zhōng bēi", english: "medium", isPunctuation: nil),
                        SpeakGlossToken(chinese: "珍珠奶茶", pinyin: "zhēn zhū nǎi chá", english: "bubble tea", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "半糖", pinyin: "bàn táng", english: "half sugar", isPunctuation: nil),
                        SpeakGlossToken(chinese: "少冰", pinyin: "shǎo bīng", english: "less ice", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 2,
                aiLine: SpeakLine(
                    chinese: "要加料嗎？有波霸和椰果。",
                    pinyin: "yào jiā liào ma? yǒu bō bà hé yé guǒ.",
                    english: "Want toppings? We have boba and coconut jelly.",
                    gloss: [
                        SpeakGlossToken(chinese: "要", pinyin: "yào", english: "want", isPunctuation: nil),
                        SpeakGlossToken(chinese: "加料", pinyin: "jiā liào", english: "add toppings", isPunctuation: nil),
                        SpeakGlossToken(chinese: "嗎", pinyin: "ma", english: "question particle", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "有", pinyin: "yǒu", english: "have", isPunctuation: nil),
                        SpeakGlossToken(chinese: "波霸", pinyin: "bō bà", english: "boba pearls", isPunctuation: nil),
                        SpeakGlossToken(chinese: "和", pinyin: "hé", english: "and", isPunctuation: nil),
                        SpeakGlossToken(chinese: "椰果", pinyin: "yé guǒ", english: "coconut jelly", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "加波霸，冰塊少一點，謝謝。",
                    pinyin: "jiā bō bà, bīng kuài shǎo yī diǎn, xiè xie.",
                    english: "Add boba, less ice, thanks.",
                    gloss: [
                        SpeakGlossToken(chinese: "加", pinyin: "jiā", english: "add", isPunctuation: nil),
                        SpeakGlossToken(chinese: "波霸", pinyin: "bō bà", english: "boba", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "冰塊", pinyin: "bīng kuài", english: "ice cubes", isPunctuation: nil),
                        SpeakGlossToken(chinese: "少一點", pinyin: "shǎo yī diǎn", english: "a bit less", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "謝謝", pinyin: "xiè xie", english: "thanks", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 3,
                aiLine: SpeakLine(
                    chinese: "需要留名字嗎？怎麼付款？",
                    pinyin: "xū yào liú míng zi ma? zěn me fù kuǎn?",
                    english: "Need a name and how will you pay?",
                    gloss: [
                        SpeakGlossToken(chinese: "需要", pinyin: "xū yào", english: "need", isPunctuation: nil),
                        SpeakGlossToken(chinese: "留", pinyin: "liú", english: "leave", isPunctuation: nil),
                        SpeakGlossToken(chinese: "名字", pinyin: "míng zi", english: "name", isPunctuation: nil),
                        SpeakGlossToken(chinese: "嗎", pinyin: "ma", english: "question particle", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "怎麼", pinyin: "zěn me", english: "how", isPunctuation: nil),
                        SpeakGlossToken(chinese: "付款", pinyin: "fù kuǎn", english: "pay", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "名字寫阿力克斯，用悠遊卡。",
                    pinyin: "míng zi xiě ā lì kè sī, yòng yōu yóu kǎ.",
                    english: "Write the name Alex; I’ll use EasyCard.",
                    gloss: [
                        SpeakGlossToken(chinese: "名字", pinyin: "míng zi", english: "name", isPunctuation: nil),
                        SpeakGlossToken(chinese: "寫", pinyin: "xiě", english: "write", isPunctuation: nil),
                        SpeakGlossToken(chinese: "阿力克斯", pinyin: "ā lì kè sī", english: "Alex", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "用", pinyin: "yòng", english: "use", isPunctuation: nil),
                        SpeakGlossToken(chinese: "悠遊卡", pinyin: "yōu yóu kǎ", english: "EasyCard", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 4,
                aiLine: SpeakLine(
                    chinese: "好的，三到五分鐘，請在取餐口等。",
                    pinyin: "hǎo de, sān dào wǔ fēn zhōng, qǐng zài qǔ cān kǒu děng.",
                    english: "Great—3 to 5 minutes; please wait at pickup.",
                    gloss: [
                        SpeakGlossToken(chinese: "好的", pinyin: "hǎo de", english: "okay", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "三到五分鐘", pinyin: "sān dào wǔ fēn zhōng", english: "3 to 5 minutes", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "請", pinyin: "qǐng", english: "please", isPunctuation: nil),
                        SpeakGlossToken(chinese: "在", pinyin: "zài", english: "at", isPunctuation: nil),
                        SpeakGlossToken(chinese: "取餐口", pinyin: "qǔ cān kǒu", english: "pickup counter", isPunctuation: nil),
                        SpeakGlossToken(chinese: "等", pinyin: "děng", english: "wait", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "好，麻煩你，謝謝。",
                    pinyin: "hǎo, má fán nǐ, xiè xie.",
                    english: "Okay, thank you.",
                    gloss: [
                        SpeakGlossToken(chinese: "好", pinyin: "hǎo", english: "okay", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "麻煩你", pinyin: "má fán nǐ", english: "thanks for your help", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "謝謝", pinyin: "xiè xie", english: "thank you", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            )
        ]
    )

    private static let nightMarket = SceneContent(
        scene: SpeakScene(
            id: nightMarketId,
            title: "Night Market Snacks",
            description: "Buy night market snacks and ask about prices or spice levels.",
            tags: ["food", "nightmarket", "snacks"],
            level: .beginner,
            createdAt: nil
        ),
        outline: SpeakChatOutline(
            sceneId: nightMarketId,
            turns: [
                SpeakTurnOutline(
                    step: 1,
                    speakFirst: .ai,
                    aiIntent: "Greet and ask what the customer wants.",
                    userIntent: "Order small stinky tofu and ask for less spice.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 2,
                    speakFirst: .ai,
                    aiIntent: "Offer spice levels or no spice.",
                    userIntent: "Choose mild and add pickled cabbage.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 3,
                    speakFirst: .ai,
                    aiIntent: "Suggest another item.",
                    userIntent: "Add sweet potato balls.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 4,
                    speakFirst: .ai,
                    aiIntent: "Give total and wait time.",
                    userIntent: "Pay cash and thank them.",
                    focusHint: nil
                )
            ],
            practiceTip: "Use the measure word yi fen and soften with jiu hao or xie xie."
        ),
        turns: [
            SpeakTurn(
                step: 1,
                aiLine: SpeakLine(
                    chinese: "你好，要吃點什麼？",
                    pinyin: "nǐ hǎo, yào chī diǎn shén me?",
                    english: "Hi! What would you like to eat?",
                    gloss: [
                        SpeakGlossToken(chinese: "你好", pinyin: "nǐ hǎo", english: "hello", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "要", pinyin: "yào", english: "want to", isPunctuation: nil),
                        SpeakGlossToken(chinese: "吃", pinyin: "chī", english: "eat", isPunctuation: nil),
                        SpeakGlossToken(chinese: "點", pinyin: "diǎn", english: "some", isPunctuation: nil),
                        SpeakGlossToken(chinese: "什麼", pinyin: "shén me", english: "what", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "想要一份小份臭豆腐，可以少辣嗎？",
                    pinyin: "xiǎng yào yī fèn xiǎo fèn chòu dòu fǔ, kě yǐ shǎo là ma?",
                    english: "I’d like a small stinky tofu; can it be less spicy?",
                    gloss: [
                        SpeakGlossToken(chinese: "想要", pinyin: "xiǎng yào", english: "would like", isPunctuation: nil),
                        SpeakGlossToken(chinese: "一份", pinyin: "yī fèn", english: "one order", isPunctuation: nil),
                        SpeakGlossToken(chinese: "小份", pinyin: "xiǎo fèn", english: "small portion", isPunctuation: nil),
                        SpeakGlossToken(chinese: "臭豆腐", pinyin: "chòu dòu fǔ", english: "stinky tofu", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "可以", pinyin: "kě yǐ", english: "can", isPunctuation: nil),
                        SpeakGlossToken(chinese: "少辣", pinyin: "shǎo là", english: "less spicy", isPunctuation: nil),
                        SpeakGlossToken(chinese: "嗎", pinyin: "ma", english: "question particle", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 2,
                aiLine: SpeakLine(
                    chinese: "可以，微辣或不辣都行。",
                    pinyin: "kě yǐ, wēi là huò bù là dōu xíng.",
                    english: "Sure—mild or no spice both work.",
                    gloss: [
                        SpeakGlossToken(chinese: "可以", pinyin: "kě yǐ", english: "can", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "微辣", pinyin: "wēi là", english: "mild spicy", isPunctuation: nil),
                        SpeakGlossToken(chinese: "或", pinyin: "huò", english: "or", isPunctuation: nil),
                        SpeakGlossToken(chinese: "不辣", pinyin: "bù là", english: "not spicy", isPunctuation: nil),
                        SpeakGlossToken(chinese: "都", pinyin: "dōu", english: "both", isPunctuation: nil),
                        SpeakGlossToken(chinese: "行", pinyin: "xíng", english: "ok", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "微辣就好，加一點泡菜。",
                    pinyin: "wēi là jiù hǎo, jiā yī diǎn pào cài.",
                    english: "Mild is good; add some pickled cabbage.",
                    gloss: [
                        SpeakGlossToken(chinese: "微辣", pinyin: "wēi là", english: "mild spicy", isPunctuation: nil),
                        SpeakGlossToken(chinese: "就", pinyin: "jiù", english: "just", isPunctuation: nil),
                        SpeakGlossToken(chinese: "好", pinyin: "hǎo", english: "good", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "加", pinyin: "jiā", english: "add", isPunctuation: nil),
                        SpeakGlossToken(chinese: "一點", pinyin: "yī diǎn", english: "a bit", isPunctuation: nil),
                        SpeakGlossToken(chinese: "泡菜", pinyin: "pào cài", english: "pickled cabbage", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 3,
                aiLine: SpeakLine(
                    chinese: "要不要試試地瓜球？",
                    pinyin: "yào bù yào shì shì dì guā qiú?",
                    english: "How about sweet potato balls?",
                    gloss: [
                        SpeakGlossToken(chinese: "要不要", pinyin: "yào bù yào", english: "would you like", isPunctuation: nil),
                        SpeakGlossToken(chinese: "試試", pinyin: "shì shì", english: "try", isPunctuation: nil),
                        SpeakGlossToken(chinese: "地瓜球", pinyin: "dì guā qiú", english: "sweet potato balls", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "好啊，加一份地瓜球。",
                    pinyin: "hǎo a, jiā yī fèn dì guā qiú.",
                    english: "Sure, add one order of sweet potato balls.",
                    gloss: [
                        SpeakGlossToken(chinese: "好啊", pinyin: "hǎo a", english: "sure", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "加", pinyin: "jiā", english: "add", isPunctuation: nil),
                        SpeakGlossToken(chinese: "一份", pinyin: "yī fèn", english: "one order", isPunctuation: nil),
                        SpeakGlossToken(chinese: "地瓜球", pinyin: "dì guā qiú", english: "sweet potato balls", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 4,
                aiLine: SpeakLine(
                    chinese: "總共一百二，等五分鐘可以嗎？",
                    pinyin: "zǒng gòng yī bǎi èr, děng wǔ fēn zhōng kě yǐ ma?",
                    english: "That’s 120 NT. Is a 5-minute wait okay?",
                    gloss: [
                        SpeakGlossToken(chinese: "總共", pinyin: "zǒng gòng", english: "in total", isPunctuation: nil),
                        SpeakGlossToken(chinese: "一百二", pinyin: "yī bǎi èr", english: "120 NT", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "等", pinyin: "děng", english: "wait", isPunctuation: nil),
                        SpeakGlossToken(chinese: "五分鐘", pinyin: "wǔ fēn zhōng", english: "5 minutes", isPunctuation: nil),
                        SpeakGlossToken(chinese: "可以", pinyin: "kě yǐ", english: "okay", isPunctuation: nil),
                        SpeakGlossToken(chinese: "嗎", pinyin: "ma", english: "question particle", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "可以，給你一百二，謝謝。",
                    pinyin: "kě yǐ, gěi nǐ yī bǎi èr, xiè xie.",
                    english: "Sure. Here’s 120. Thanks.",
                    gloss: [
                        SpeakGlossToken(chinese: "可以", pinyin: "kě yǐ", english: "okay", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "給", pinyin: "gěi", english: "give", isPunctuation: nil),
                        SpeakGlossToken(chinese: "你", pinyin: "nǐ", english: "you", isPunctuation: nil),
                        SpeakGlossToken(chinese: "一百二", pinyin: "yī bǎi èr", english: "120 NT", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "謝謝", pinyin: "xiè xie", english: "thanks", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            )
        ]
    )

    private static let mrtTopUp = SceneContent(
        scene: SpeakScene(
            id: mrtTopUpId,
            title: "MRT EasyCard Top-Up",
            description: "Top up an EasyCard at the MRT station and confirm the balance.",
            tags: ["transit", "topup", "payments"],
            level: .beginner,
            createdAt: nil
        ),
        outline: SpeakChatOutline(
            sceneId: mrtTopUpId,
            turns: [
                SpeakTurnOutline(
                    step: 1,
                    speakFirst: .ai,
                    aiIntent: "Greet and ask how much to add.",
                    userIntent: "Request to add 300 NTD to the EasyCard.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 2,
                    speakFirst: .ai,
                    aiIntent: "Confirm amount and payment method.",
                    userIntent: "Confirm cash payment.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 3,
                    speakFirst: .ai,
                    aiIntent: "Share new balance and return the card.",
                    userIntent: "Confirm receipt and ask about auto top-up.",
                    focusHint: nil
                ),
                SpeakTurnOutline(
                    step: 4,
                    speakFirst: .ai,
                    aiIntent: "Explain auto top-up or thank the customer.",
                    userIntent: "Thank them and end the interaction.",
                    focusHint: nil
                )
            ],
            practiceTip: "Use qǐng and kěyǐ for polite requests; confirm amounts clearly."
        ),
        turns: [
            SpeakTurn(
                step: 1,
                aiLine: SpeakLine(
                    chinese: "您好，要加值多少呢？",
                    pinyin: "nín hǎo, yào jiā zhí duō shǎo ne?",
                    english: "Hello, how much would you like to add?",
                    gloss: [
                        SpeakGlossToken(chinese: "您好", pinyin: "nín hǎo", english: "hello (polite)", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "要", pinyin: "yào", english: "want to", isPunctuation: nil),
                        SpeakGlossToken(chinese: "加值", pinyin: "jiā zhí", english: "top up", isPunctuation: nil),
                        SpeakGlossToken(chinese: "多少", pinyin: "duō shǎo", english: "how much", isPunctuation: nil),
                        SpeakGlossToken(chinese: "呢", pinyin: "ne", english: "particle", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "請幫我加三百元。",
                    pinyin: "qǐng bāng wǒ jiā sān bǎi yuán.",
                    english: "Please add 300 NTD.",
                    gloss: [
                        SpeakGlossToken(chinese: "請", pinyin: "qǐng", english: "please", isPunctuation: nil),
                        SpeakGlossToken(chinese: "幫我", pinyin: "bāng wǒ", english: "help me", isPunctuation: nil),
                        SpeakGlossToken(chinese: "加", pinyin: "jiā", english: "add", isPunctuation: nil),
                        SpeakGlossToken(chinese: "三百元", pinyin: "sān bǎi yuán", english: "300 dollars", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 2,
                aiLine: SpeakLine(
                    chinese: "好的，加三百，用現金嗎？",
                    pinyin: "hǎo de, jiā sān bǎi, yòng xiàn jīn ma?",
                    english: "Okay, adding 300. Paying cash?",
                    gloss: [
                        SpeakGlossToken(chinese: "好的", pinyin: "hǎo de", english: "okay", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "加", pinyin: "jiā", english: "add", isPunctuation: nil),
                        SpeakGlossToken(chinese: "三百", pinyin: "sān bǎi", english: "300", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "用", pinyin: "yòng", english: "use", isPunctuation: nil),
                        SpeakGlossToken(chinese: "現金", pinyin: "xiàn jīn", english: "cash", isPunctuation: nil),
                        SpeakGlossToken(chinese: "嗎", pinyin: "ma", english: "question particle", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "對，用現金。",
                    pinyin: "duì, yòng xiàn jīn.",
                    english: "Yes, cash.",
                    gloss: [
                        SpeakGlossToken(chinese: "對", pinyin: "duì", english: "yes", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "用", pinyin: "yòng", english: "use", isPunctuation: nil),
                        SpeakGlossToken(chinese: "現金", pinyin: "xiàn jīn", english: "cash", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 3,
                aiLine: SpeakLine(
                    chinese: "加好了，現在餘額六百五，這是卡。",
                    pinyin: "jiā hǎo le, xiàn zài yú é liù bǎi wǔ, zhè shì kǎ.",
                    english: "Top-up complete. Balance is 650. Here’s your card.",
                    gloss: [
                        SpeakGlossToken(chinese: "加好", pinyin: "jiā hǎo", english: "added", isPunctuation: nil),
                        SpeakGlossToken(chinese: "了", pinyin: "le", english: "completed", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "現在", pinyin: "xiàn zài", english: "now", isPunctuation: nil),
                        SpeakGlossToken(chinese: "餘額", pinyin: "yú é", english: "balance", isPunctuation: nil),
                        SpeakGlossToken(chinese: "六百五", pinyin: "liù bǎi wǔ", english: "650", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "這是", pinyin: "zhè shì", english: "here is", isPunctuation: nil),
                        SpeakGlossToken(chinese: "卡", pinyin: "kǎ", english: "card", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "謝謝，之後可以自動加值嗎？",
                    pinyin: "xiè xie, zhī hòu kě yǐ zì dòng jiā zhí ma?",
                    english: "Thanks—can it auto top-up later?",
                    gloss: [
                        SpeakGlossToken(chinese: "謝謝", pinyin: "xiè xie", english: "thanks", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "之後", pinyin: "zhī hòu", english: "later/on", isPunctuation: nil),
                        SpeakGlossToken(chinese: "可以", pinyin: "kě yǐ", english: "can", isPunctuation: nil),
                        SpeakGlossToken(chinese: "自動", pinyin: "zì dòng", english: "automatic", isPunctuation: nil),
                        SpeakGlossToken(chinese: "加值", pinyin: "jiā zhí", english: "top up", isPunctuation: nil),
                        SpeakGlossToken(chinese: "嗎", pinyin: "ma", english: "question particle", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "？", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            ),
            SpeakTurn(
                step: 4,
                aiLine: SpeakLine(
                    chinese: "可以在便利商店設定，或現在先用現金。謝謝。",
                    pinyin: "kě yǐ zài biàn lì shāng diàn shè dìng, huò xiàn zài xiān yòng xiàn jīn. xiè xie.",
                    english: "You can set it up at a convenience store, or keep using cash. Thank you.",
                    gloss: [
                        SpeakGlossToken(chinese: "可以", pinyin: "kě yǐ", english: "can", isPunctuation: nil),
                        SpeakGlossToken(chinese: "在", pinyin: "zài", english: "at", isPunctuation: nil),
                        SpeakGlossToken(chinese: "便利商店", pinyin: "biàn lì shāng diàn", english: "convenience store", isPunctuation: nil),
                        SpeakGlossToken(chinese: "設定", pinyin: "shè dìng", english: "set up", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "或", pinyin: "huò", english: "or", isPunctuation: nil),
                        SpeakGlossToken(chinese: "現在", pinyin: "xiàn zài", english: "now", isPunctuation: nil),
                        SpeakGlossToken(chinese: "先", pinyin: "xiān", english: "first", isPunctuation: nil),
                        SpeakGlossToken(chinese: "用", pinyin: "yòng", english: "use", isPunctuation: nil),
                        SpeakGlossToken(chinese: "現金", pinyin: "xiàn jīn", english: "cash", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "謝謝", pinyin: "xiè xie", english: "thank you", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                userLine: SpeakLine(
                    chinese: "好的，謝謝。",
                    pinyin: "hǎo de, xiè xie.",
                    english: "Got it, thanks.",
                    gloss: [
                        SpeakGlossToken(chinese: "好的", pinyin: "hǎo de", english: "okay", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "，", english: "", isPunctuation: true),
                        SpeakGlossToken(chinese: "謝謝", pinyin: "xiè xie", english: "thank you", isPunctuation: nil),
                        SpeakGlossToken(chinese: nil, pinyin: "。", english: "", isPunctuation: true)
                    ],
                    cue: nil
                ),
                speakFirst: .ai,
                focusHint: nil
            )
        ]
    )
}
