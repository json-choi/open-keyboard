package io.github.jsonchoi.openkeyboard

/** A fixed, local emoji list; the keyboard never downloads emoji data. */
object EmojiCatalog {
    data class Category(val symbol: String, val title: Int, val emoji: String)
    val groups = listOf(
        Category("😀", R.string.emoji_people, "😀 😃 😄 😁 😆 😅 😂 🤣 😊 🙂 🙃 😉 😍 🥰 😘 😋 😎 🤩 🥳 😏 😌 🥹 🥲 😭 😢 😤 😠 🤔 🤨 😐 🙄 😴 😪 🤒 🤧 😷 🤯 😱 😳 🫠 🫡 🤗 🤭 🫣 🤫 🤐 🫶 👋 🤚 ✋ 🖖 👌 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 👍 👎 👏 🙌 🙏 💪 👀 🧑‍💻 👩‍💻 👨‍💻 👨‍👩‍👧‍👦"),
        Category("🐻", R.string.emoji_nature, "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦋 🐝 🐞 🐢 🐍 🦎 🐙 🦑 🦐 🦀 🐠 🐟 🐬 🐳 🦈 🐘 🦒 🦔 🌵 🎄 🌲 🌳 🌴 🌱 🌿 🍀 🍁 🍂 🍄 🌸 🌼 🌻 🌹 🌷 🌺 🌞 🌝 🌙 ⭐ 🌟 ✨ ⚡ 🌈 ☀️ ☁️ 🌧️ ❄️ 🔥 💧 🌊"),
        Category("🍎", R.string.emoji_food, "🍎 🍏 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🌽 🥕 🥔 🍞 🥐 🥨 🥯 🧀 🥚 🍳 🥞 🥓 🥩 🍗 🍔 🍟 🍕 🌭 🥪 🌮 🌯 🍜 🍲 🍛 🍣 🍱 🥟 🍚 🍙 🍘 🍢 🍡 🍦 🍧 🍨 🍩 🍪 🎂 🍰 🧁 🍫 🍬 🍭 ☕ 🍵 🧋 🥤 🍺 🍻 🥂 🍷 🥃"),
        Category("⚽", R.string.emoji_activities, "⚽ 🏀 🏈 ⚾ 🎾 🏐 🏉 🎱 🏓 🏸 🏒 🏹 ⛳ ⛷️ 🏂 🏄 🏊 🚴 🏃 🧘 🏆 🥇 🥈 🥉 🎖️ 🎯 🎮 🎲 🎳 🎸 🎹 🎤 🎧 🎨 🎬 🎭 🎪 🚗 🚕 🚙 🚌 🚎 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚲 🛵 🏍️ 🚆 🚇 🚅 ✈️ 🚀 🚁 ⛵ 🚢 🛶 🗺️ 🏠 🏡 🏢 🏫 🏥 🏰 🗼 🗽 🏝️ 🏖️ 🏕️ ⛰️ 🗻"),
        Category("💡", R.string.emoji_objects, "💡 🔦 🕯️ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 💾 📷 📹 🎥 📺 📻 ⏰ ⌚ ⏳ 🔋 🔌 📖 📚 📕 📓 📔 📝 ✏️ 🖊️ 🖍️ 📌 📎 📏 ✂️ 📁 📂 🗂️ 📅 📆 📊 📈 📉 📋 📮 📬 ✉️ 📧 📦 🎁 🎈 🎉 🎊 🧸 🪄 🪴 🛏️ 🛋️ 🚪 🪑 🛁 🪞 🔑 🔒 🔓 🔔 🔕 💰 💳 💎 🛒 🧳 ☂️ 🕶️ 👓 👟"),
        Category("❤️", R.string.emoji_symbols, "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 🩷 🩵 🩶 💔 ❤️‍🔥 💕 💞 💓 💗 💖 💘 💝 💟 💌 💯 ✅ ☑️ ✔️ ❌ ❎ ⚠️ 🚫 ⛔ 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔶 🔷 🔸 🔹 🔲 🔳 ⬛ ⬜ 🟥 🟧 🟨 🟩 🟦 🟪 🟫 ➕ ➖ ➗ ✖️ ♾️ ❓ ❔ ❗ ❕ ‼️ ⁉️ ➡️ ⬅️ ⬆️ ⬇️ 🔄 🔃 🔙 🔝 🆗 🆕 🆙 🆒 🆓"),
    )
}
