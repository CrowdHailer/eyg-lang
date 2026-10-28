package expo.modules.eyg

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.functions.Coroutine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Sessions own their Zig arena. JNI handles never cross into JavaScript. */
class EygRuntimeModule : Module() {
  private val sessions = NativeSessions(EygNative)

  override fun definition() = ModuleDefinition {
    Name("EygRuntime")
    Function("pureSync") { request: String ->
      // Isolated, data-only VM with a strict step/memory/input budget. It never
      // borrows an async session and cannot make a phone/native effect call.
      String(EygNative.pure(request.toByteArray(Charsets.UTF_8)), Charsets.UTF_8)
    }
    AsyncFunction("create") Coroutine {
      withContext(Dispatchers.IO) { sessions.create() }
    }
    AsyncFunction("evaluate") Coroutine { id: Int, request: String ->
      withContext(Dispatchers.IO) { sessions.call(id, request, false) }
    }
    AsyncFunction("resume") Coroutine { id: Int, reply: String ->
      withContext(Dispatchers.IO) { sessions.call(id, reply, true) }
    }
    AsyncFunction("destroy") Coroutine { id: Int ->
      withContext(Dispatchers.IO) { sessions.destroy(id) }
    }
    OnDestroy {
      sessions.close()
    }
  }

}
