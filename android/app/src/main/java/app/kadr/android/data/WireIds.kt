package app.kadr.android.data

import kotlinx.serialization.json.*
import java.util.UUID

object WireIds {
    private val fields = setOf("id", "owner", "entityID", "authorID", "senderID", "recipientID", "parentID", "replyTo", "postID", "messageID", "commentID")
    private val lists = setOf("ids", "likes", "blocked", "hiddenPosts", "hiddenAuthors", "pinnedPosts", "pinnedChats")
    fun canonical(value: String): String = if (value.length == 36) runCatching { UUID.fromString(value).toString() }.getOrDefault(value) else value
    fun normalize(element: JsonElement, field: String = ""): JsonElement = when (element) {
        is JsonObject -> JsonObject(element.mapKeys { canonical(it.key) }.mapValues { (key, value) -> normalize(value, key) })
        is JsonArray -> JsonArray(element.map { if (field in lists && it is JsonPrimitive && it.isString) JsonPrimitive(canonical(it.content)) else normalize(it) })
        is JsonPrimitive -> if (field in fields && element.isString) JsonPrimitive(canonical(element.content)) else element
    }
}
