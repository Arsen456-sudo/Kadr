package app.kadr.android.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.UUID

val Codec = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false; coerceInputValues = true }
fun newId(): String = UUID.randomUUID().toString()
// Match Foundation.JSONEncoder's reference date (2001-01-01), including chat resources.
fun now(): Double = System.currentTimeMillis() / 1000.0 - 978307200.0

@Serializable data class Profile(val id: String = newId(), val handle: String, val name: String, val bio: String = "", val avatar: String? = null, val portraitFile: String? = null, val bannerFile: String? = null)
@Serializable data class PostMedia(val id: String = newId(), val kind: String, val file: String, val remoteURL: String? = null)
@Serializable data class PostOptions(val tags: String = "", val location: String = "", val allowsComments: Boolean = true, val onlyMe: Boolean = false, val coverIndex: Int = 0)
@Serializable data class PostExtras(val albumLayout: String = "pages", val photoCaptions: Map<String, String> = emptyMap(), val hideLikeCount: Boolean = false, val trimStart: Double = 0.0, val trimEnd: Double? = null, val coverTime: Double = 0.5, val collageGap: Double = 4.0)
@Serializable data class Post(val id: String = newId(), val authorID: String? = null, val caption: String = "", val file: String = "", val credit: String = "", val media: List<PostMedia> = emptyList(), val options: PostOptions = PostOptions(), val createdAt: Double = now(), val isDraft: Boolean = false, val extras: PostExtras = PostExtras()) {
    val photo: Boolean get() = media.firstOrNull()?.kind == "photo"
    val items: List<PostMedia> get() = media.ifEmpty { listOf(PostMedia(id = id, kind = "video", file = if (authorID == null && file in setOf("bunny", "sintel")) "$file.mp4" else file)) }
}
@Serializable data class Comment(val id: String = newId(), val authorID: String, val text: String, val parentID: String? = null, val likes: Set<String> = emptySet(), val pinned: Boolean = false, val createdAt: Double = now())
@Serializable data class Message(val id: String = newId(), val senderID: String, val recipientID: String, val text: String, @Serializable(with = FoundationDateSerializer::class) val createdAt: Double = now(), val replyTo: String? = null, val reactions: Map<String, String> = emptyMap(), val edited: Boolean = false, val attachmentFile: String? = null, val attachmentKind: String? = null, val postID: String? = null)
@Serializable data class Appearance(val theme: String = "atmosphere", val accent: String = "peach", val introduction: String = "", val links: List<String> = emptyList(), val pinnedPosts: List<String> = emptyList(), val bannerStart: Double = 0.0, val interests: List<String> = emptyList())
@Serializable data class Preferences(val haptics: Boolean = true, val autoSound: Boolean = false, val playbackRate: Float = 1f, val mediaFilter: String = "all", val messagePermission: String = "following", val blocked: Set<String> = emptySet(), val hiddenPosts: Set<String> = emptySet(), val hiddenAuthors: Set<String> = emptySet(), val preferredTags: Set<String> = emptySet(), val mutedWords: List<String> = emptyList())
@Serializable data class Collection(val id: String = newId(), val title: String, val posts: List<String> = emptyList(), val cover: String? = null)
@Serializable data class Watch(val postID: String, val seconds: Double, val duration: Double, val updatedAt: Double = now())
@Serializable data class Studio(val appearance: Appearance = Appearance(), val preferences: Preferences = Preferences(), val collections: List<Collection> = emptyList(), val notes: Map<String, String> = emptyMap(), val watches: Map<String, Watch> = emptyMap(), val searches: List<String> = emptyList(), val chatDrafts: Map<String, String> = emptyMap(), val pinnedChats: Set<String> = emptySet())
@Serializable data class ResourceRecord(val owner: String, val resource: String, val entityID: String, val payload: String)
@Serializable data class SyncPage(val records: List<ResourceRecord> = emptyList(), val cursor: Int = 0)
@Serializable data class AppState(val schema: Int = 1, val profiles: List<Profile> = emptyList(), val activeID: String? = null, val posts: List<Post> = emptyList(), val likes: Map<String, Set<String>> = emptyMap(), val bookmarks: Map<String, Set<String>> = emptyMap(), val comments: Map<String, List<Comment>> = emptyMap(), val following: Map<String, Set<String>> = emptyMap(), val messages: List<Message> = emptyList(), val studios: Map<String, Studio> = emptyMap(), val outbox: List<ResourceRecord> = emptyList(), val cursors: Map<String, Int> = emptyMap(), val welcomed: Boolean = false) {
    val active: Profile? get() = profiles.find { it.id.equals(activeID, true) }
    val studio: Studio get() = studios[activeID ?: "guest"] ?: Studio()
    companion object { val samples = listOf(Post(id = "bunny", caption = "Big Buck Bunny • маленька історія великого кролика", file = "bunny", credit = "Blender Foundation · CC BY 3.0"), Post(id = "sintel", caption = "Sintel • подорож, яку хочеться продовжити", file = "sintel", credit = "Blender Foundation · CC BY 3.0")) }
}

object AccountRules {
    fun normalize(handle: String) = handle.trim().removePrefix("@").lowercase(java.util.Locale.ROOT)
    fun validate(handle: String, name: String, profiles: List<Profile>, owner: String? = null): String? {
        val normalized = normalize(handle)
        if (!Regex("[a-z0-9_]{3,24}").matches(normalized)) return "Нікнейм: 3–24 латинські літери, цифри або _."
        if (profiles.any { it.id != owner && it.handle.equals(normalized, true) }) return "Цей @нікнейм уже зайнятий. Зміни хоча б один символ."
        if (name.trim().isEmpty() || name.trim().length > 200) return "Вкажи імʼя від 1 до 200 символів."
        return null
    }
}
