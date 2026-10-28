package expo.modules.eyg

import java.util.concurrent.Executors

internal interface NativeBackend {
  fun create(): Long
  fun evaluate(session: Long, request: ByteArray): ByteArray
  fun resume(session: Long, reply: ByteArray): ByteArray
  fun cancel(session: Long)
  fun destroy(session: Long)
}

/** Owns native pointers; only integer IDs cross the JavaScript boundary. */
internal class NativeSessions(private val native: NativeBackend) : AutoCloseable {
  private class Session(val pointer: Long) {
    val serial = Any()
    var calls = 0
    var closed = false
  }

  private val sessions = mutableMapOf<Int, Session>()
  private val ownership = Any()
  private val disposer = Executors.newSingleThreadExecutor()
  private var nextId = 1
  private var closed = false

  fun create(): Int {
    synchronized(ownership) { check(!closed) { "Zig runtime has been destroyed" } }
    val pointer = native.create()
    check(pointer != 0L) { "Unable to allocate Zig interpreter" }
    val id = synchronized(ownership) {
      if (closed) null else nextId++.also { sessions[it] = Session(pointer) }
    }
    if (id != null) return id
    // Creation runs on an IO worker. Shutdown can win without waiting for it.
    native.destroy(pointer)
    error("Zig runtime has been destroyed")
  }

  fun call(id: Int, text: String, resume: Boolean): String {
    val session = synchronized(ownership) {
      (sessions[id] ?: error("Closed Zig session")).also { it.calls++ }
    }
    try {
      synchronized(session.serial) {
        check(synchronized(ownership) { !session.closed }) { "Closed Zig session" }
        val input = text.toByteArray(Charsets.UTF_8)
        val output = if (resume) native.resume(session.pointer, input) else native.evaluate(session.pointer, input)
        return output.toString(Charsets.UTF_8)
      }
    } finally {
      val lastOwner = synchronized(ownership) {
        session.calls--
        session.closed && session.calls == 0
      }
      if (lastOwner) native.destroy(session.pointer)
    }
  }

  /** Called by the Expo module's IO dispatcher; a live call keeps ownership. */
  fun destroy(id: Int) {
    val idle = synchronized(ownership) {
      sessions[id]?.let { session ->
        // Holding ownership prevents the last IO worker from freeing this
        // pointer while the lock-free native cancellation flag is being set.
        if (session.calls > 0) native.cancel(session.pointer)
        sessions.remove(id)
        session.closed = true
        session.takeIf { it.calls == 0 }
      }
    }
    idle?.let { native.destroy(it.pointer) }
  }

  /** Does not join IO workers or acquire a session's evaluation lock. */
  override fun close() {
    val idle = synchronized(ownership) {
      if (closed) return
      closed = true
      val owned = sessions.values.toList()
      owned.forEach {
        if (it.calls > 0) native.cancel(it.pointer)
        it.closed = true
      }
      sessions.clear()
      owned.filter { it.calls == 0 }
    }
    // Idle arenas may be large. Free them off the lifecycle/UI thread too.
    // Active calls release their final pointer in their own IO worker.
    disposer.execute { idle.forEach { native.destroy(it.pointer) } }
    disposer.shutdown()
  }
}
