package app.kadr.android

import app.kadr.android.data.*
import kotlinx.serialization.encodeToString
import org.junit.Assert.*
import org.junit.Test

class ContractTest {
    @Test fun wireUUIDNormalizationPreservesUserText() {
        val upper = "8D11635D-6261-4C1F-8ABC-26FA652026A5"
        val source = kotlinx.serialization.json.buildJsonObject {
            put("authorID", kotlinx.serialization.json.JsonPrimitive(upper))
            put("text", kotlinx.serialization.json.JsonPrimitive("ABC " + upper))
        }
        val value = WireIds.normalize(source) as kotlinx.serialization.json.JsonObject
        assertEquals(upper.lowercase(), (value["authorID"] as kotlinx.serialization.json.JsonPrimitive).content)
        assertEquals("ABC " + upper, (value["text"] as kotlinx.serialization.json.JsonPrimitive).content)
    }
    @Test fun handlesAreUniqueIgnoringCaseAndAtPrefix() {
        val person = Profile(id = "one", handle = "kadr_user", name = "Користувач")
        assertNotNull(AccountRules.validate(" @KADR_USER ", "Інший", listOf(person)))
        assertNull(AccountRules.validate("@KADR_USER", "Оновлене імʼя", listOf(person), "one"))
        assertNotNull(AccountRules.validate("bad-handle", "Імʼя", emptyList()))
        assertNotNull(AccountRules.validate("okay", "  ", emptyList()))
    }
    @Test fun foundationAndRESTDatesDecodeToTheSameInstant() {
        val common = "\"id\":\"msg\",\"senderID\":\"one\",\"recipientID\":\"two\",\"text\":\"Привіт\""
        val swift = Codec.decodeFromString<Message>("{$common,\"createdAt\":0}")
        val rest = Codec.decodeFromString<Message>("{$common,\"createdAt\":\"2001-01-01T00:00:00Z\"}")
        assertEquals(swift.createdAt, rest.createdAt, 0.001)
        assertTrue(Codec.encodeToString(swift).contains("\"createdAt\":0.0"))
    }
    @Test fun legacyIOSNullOptionsKeepUsableDefaults() {
        val post = Codec.decodeFromString<Post>("""{"id":"old","caption":"Кадр","file":"video.mp4","media":null,"options":null,"extras":null,"isDraft":null}""")
        assertTrue(post.options.allowsComments)
        assertFalse(post.isDraft)
        assertEquals("video", post.items.first().kind)
    }
    @Test fun accountPreferencesAndReactionsRemainIsolatedInSnapshots() {
        val a = Profile(id = "a", handle = "first", name = "Перший")
        val b = Profile(id = "b", handle = "second", name = "Другий")
        val value = AppState(profiles = listOf(a, b), activeID = a.id, likes = mapOf("post" to setOf(a.id)), studios = mapOf(a.id to Studio(preferences = Preferences(autoSound = true))))
        val restored = Codec.decodeFromString<AppState>(Codec.encodeToString(value)).copy(activeID = b.id)
        assertFalse(restored.activeID in restored.likes["post"].orEmpty())
        assertFalse(restored.studio.preferences.autoSound)
        assertEquals("Другий", restored.active?.name)
    }
}
