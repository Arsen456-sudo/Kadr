package app.kadr.android.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import java.time.Instant

object FoundationDateSerializer : KSerializer<Double> {
    override val descriptor = PrimitiveSerialDescriptor("FoundationDate", PrimitiveKind.DOUBLE)
    override fun serialize(encoder: Encoder, value: Double) = encoder.encodeDouble(value)
    override fun deserialize(decoder: Decoder): Double {
        if (decoder !is JsonDecoder) return decoder.decodeDouble()
        val value = decoder.decodeJsonElement().jsonPrimitive
        return value.doubleOrNull ?: (Instant.parse(value.content).toEpochMilli() / 1000.0 - 978307200.0)
    }
}
