package expo.modules.eyg

import java.util.Random
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

private fun await(latch: CountDownLatch) {
  check(latch.await(5, TimeUnit.SECONDS)) { "Timed out waiting for test worker" }
}

private fun expectClosed(action: () -> Unit) {
  val failure = runCatching(action).exceptionOrNull()
  check(failure is IllegalStateException && failure.message!!.contains("destroyed", true) ||
    failure is IllegalStateException && failure.message!!.contains("Closed", true)) { "Expected a closed-session error, got $failure" }
}

private class Backend(
  private val callGate: CountDownLatch? = null,
  private val destroyGate: CountDownLatch? = null,
  private val createGate: CountDownLatch? = null,
  expectedDestructions: Int = 1,
) : NativeBackend {
  val entered = CountDownLatch(1)
  val creating = CountDownLatch(1)
  val destroying = CountDownLatch(1)
  val destroyed = CountDownLatch(expectedDestructions)
  val calls = AtomicInteger()
  val cancellations = AtomicInteger()
  val destructions = AtomicInteger()
  val failure = AtomicReference<Throwable>()
  private val next = AtomicLong()
  private val active = ConcurrentHashMap<Long, AtomicInteger>()
  private val retired = ConcurrentHashMap<Long, AtomicInteger>()
  private val cancelled = ConcurrentHashMap<Long, AtomicInteger>()

  override fun create(): Long {
    val pointer = next.incrementAndGet()
    active[pointer] = AtomicInteger()
    creating.countDown()
    createGate?.let(::await)
    return pointer
  }

  override fun evaluate(session: Long, request: ByteArray) = execute(session, request)
  override fun resume(session: Long, reply: ByteArray) = execute(session, reply)

  override fun cancel(session: Long) {
    try {
      check(active.containsKey(session)) { "Cancelled a destroyed pointer" }
      check(retired[session]?.get() != 1) { "Cancellation raced pointer destruction" }
      check(cancelled.computeIfAbsent(session) { AtomicInteger() }.incrementAndGet() == 1) { "Double cancellation" }
      cancellations.incrementAndGet()
    } catch (error: Throwable) {
      failure.set(error)
      throw error
    }
  }

  private fun execute(pointer: Long, input: ByteArray): ByteArray {
    val count = active[pointer] ?: error("Use after destruction")
    check(count.incrementAndGet() == 1) { "Concurrent calls used one native pointer" }
    calls.incrementAndGet()
    entered.countDown()
    try {
      callGate?.let(::await)
      if (input.contentEquals("throw".toByteArray())) error("Native failure")
      return input
    } finally {
      count.decrementAndGet()
    }
  }

  override fun destroy(session: Long) {
    try {
      check(active[session]?.get() == 0) { "Destroyed a live native pointer" }
      check(retired.computeIfAbsent(session) { AtomicInteger() }.incrementAndGet() == 1) { "Double destruction" }
      destructions.incrementAndGet()
      destroying.countDown()
      destroyGate?.let(::await)
      active.remove(session)
    } catch (error: Throwable) {
      failure.set(error)
      throw error
    } finally {
      destroyed.countDown()
    }
  }

  fun verify() {
    await(destroyed)
    check(failure.get() == null) { "Native ownership violation: ${failure.get()}" }
  }
}

/** Observe that the second caller has reached a lock wait before retirement. */
private fun awaitQueued(thread: Thread) {
  val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
  while (thread.state != Thread.State.BLOCKED) {
    check(thread.isAlive && System.nanoTime() < deadline) { "Second call never queued" }
    Thread.yield()
  }
}

fun main() {
  var checks = 0

  // Closing a runtime cannot wait for a blocked native network call.
  run {
    val gate = CountDownLatch(1)
    val backend = Backend(callGate = gate)
    val manager = NativeSessions(backend)
    val executor = Executors.newFixedThreadPool(2)
    try {
      val id = manager.create()
      val call = executor.submit<String> { manager.call(id, "héllo\u0000🌱", false) }
      await(backend.entered)
      executor.submit { manager.close() }.get(1, TimeUnit.SECONDS)
      check(backend.cancellations.get() == 1)
      check(backend.destructions.get() == 0)
      gate.countDown()
      check(call.get(5, TimeUnit.SECONDS) == "héllo\u0000🌱")
      backend.verify()
      check(backend.destructions.get() == 1)
      expectClosed { manager.call(id, "late", false) }
      expectClosed { manager.create() }
      manager.close()
      checks++
    } finally {
      gate.countDown()
      manager.close()
      executor.shutdownNow()
    }
  }

  // Idle disposal also runs outside the lifecycle caller, including slow frees.
  run {
    val gate = CountDownLatch(1)
    val backend = Backend(destroyGate = gate, expectedDestructions = 2)
    val manager = NativeSessions(backend)
    val executor = Executors.newSingleThreadExecutor()
    try {
      manager.create()
      manager.create()
      executor.submit { manager.close() }.get(1, TimeUnit.SECONDS)
      await(backend.destroying)
      check(backend.destroyed.count == 2L)
      gate.countDown()
      backend.verify()
      check(backend.destructions.get() == 2)
      check(backend.cancellations.get() == 0)
      checks++
    } finally {
      gate.countDown()
      manager.close()
      executor.shutdownNow()
    }
  }

  // Shutdown can win while native allocation is still outside the ownership lock.
  run {
    val gate = CountDownLatch(1)
    val backend = Backend(createGate = gate)
    val manager = NativeSessions(backend)
    val executor = Executors.newFixedThreadPool(2)
    try {
      val create = executor.submit<Int> { manager.create() }
      await(backend.creating)
      executor.submit { manager.close() }.get(1, TimeUnit.SECONDS)
      gate.countDown()
      val failure = runCatching { create.get(5, TimeUnit.SECONDS) }.exceptionOrNull()
      check(failure is ExecutionException && failure.cause is IllegalStateException)
      backend.verify()
      check(backend.destructions.get() == 1)
      check(backend.cancellations.get() == 0)
      checks++
    } finally {
      gate.countDown()
      manager.close()
      executor.shutdownNow()
    }
  }

  // Exceptions release call ownership so explicit destruction remains possible.
  run {
    val backend = Backend()
    val manager = NativeSessions(backend)
    try {
      val id = manager.create()
      check(runCatching { manager.call(id, "throw", false) }.exceptionOrNull()?.message == "Native failure")
      manager.destroy(id)
      manager.destroy(id)
      backend.verify()
      check(backend.destructions.get() == 1)
      check(backend.cancellations.get() == 0)
      checks++
    } finally { manager.close() }
  }

  // Retirement signals cancellation once before a blocked native call returns,
  // even when another caller owns a reference while queued on the session lock.
  run {
    val gate = CountDownLatch(1)
    val backend = Backend(callGate = gate)
    val manager = NativeSessions(backend)
    val executor = Executors.newSingleThreadExecutor()
    val queuedFailure = AtomicReference<Throwable>()
    var queued: Thread? = null
    try {
      val id = manager.create()
      val call = executor.submit<String> { manager.call(id, "active", false) }
      await(backend.entered)
      queued = Thread {
        try { manager.call(id, "queued", true) }
        catch (error: Throwable) { queuedFailure.set(error) }
      }.also { it.start() }
      awaitQueued(queued!!)
      manager.destroy(id)
      manager.destroy(id)
      manager.close()
      check(backend.cancellations.get() == 1)
      check(backend.destructions.get() == 0)
      check(gate.count == 1L)
      gate.countDown()
      check(call.get(5, TimeUnit.SECONDS) == "active")
      queued!!.join(5000)
      check(!queued!!.isAlive && queuedFailure.get() is IllegalStateException)
      backend.verify()
      check(backend.calls.get() == 1)
      check(backend.cancellations.get() == 1)
      check(backend.destructions.get() == 1)
      checks++
    } finally {
      gate.countDown()
      manager.close()
      executor.shutdownNow()
      queued?.join(5000)
    }
  }

  // Seeded schedules vary evaluate/resume, queued callers and competing closes.
  val random = Random(0x455947L)
  repeat(64) {
    val gate = CountDownLatch(1)
    val backend = Backend(callGate = gate)
    val manager = NativeSessions(backend)
    val executor = Executors.newFixedThreadPool(3)
    var queued: Thread? = null
    val queuedFailure = AtomicReference<Throwable>()
    try {
      val id = manager.create()
      val resumed = random.nextBoolean()
      val call = executor.submit<String> { manager.call(id, "result", resumed) }
      await(backend.entered)
      if (random.nextBoolean()) {
        queued = Thread {
          try { manager.call(id, "must not enter native", !resumed) }
          catch (error: Throwable) { queuedFailure.set(error) }
        }.also { it.start() }
        awaitQueued(queued!!)
      }
      val retire = executor.submit { manager.destroy(id) }
      val close = executor.submit { manager.close() }
      retire.get(1, TimeUnit.SECONDS)
      close.get(1, TimeUnit.SECONDS)
      check(backend.destructions.get() == 0)
      check(backend.cancellations.get() == 1)
      gate.countDown()
      check(call.get(5, TimeUnit.SECONDS) == "result")
      queued?.let {
        it.join(5000)
        check(!it.isAlive)
        check(queuedFailure.get() is IllegalStateException)
      }
      backend.verify()
      check(backend.calls.get() == 1)
      check(backend.destructions.get() == 1)
      check(backend.cancellations.get() == 1)
      checks++
    } finally {
      gate.countDown()
      manager.close()
      executor.shutdownNow()
      queued?.join(5000)
    }
  }
  println("{\"kotlinLifecycleChecks\":$checks,\"seededSchedules\":64,\"seed\":\"0x455947\",\"nativeOwnership\":\"passed\",\"nativeCancellation\":\"passed\"}")
}
