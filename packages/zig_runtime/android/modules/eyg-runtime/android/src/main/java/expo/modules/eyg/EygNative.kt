package expo.modules.eyg

/** Method names are the JNI ABI exported by eyg_jni.c. */
internal object EygNative : NativeBackend {
  init { System.loadLibrary("eyg_jni") }
  external override fun create(): Long
  external override fun evaluate(session: Long, request: ByteArray): ByteArray
  external override fun resume(session: Long, reply: ByteArray): ByteArray
  external override fun cancel(session: Long)
  external fun pure(request: ByteArray): ByteArray
  external override fun destroy(session: Long)
}
