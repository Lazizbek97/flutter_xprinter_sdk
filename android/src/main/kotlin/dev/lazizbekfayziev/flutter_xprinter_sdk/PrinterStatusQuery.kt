package dev.lazizbekfayziev.flutter_xprinter_sdk

/** Serializes status reads while allowing the vendor callback to run on the main looper. */
internal class PrinterStatusQuery(
    private val post: (Runnable) -> Unit,
    private val postDelayed: (Runnable, Long) -> Unit,
    private val removeCallbacks: (Runnable) -> Unit,
) {
    private class Reply(val success: (Int) -> Unit, val error: (Throwable) -> Unit)
    private class Request(val replies: MutableList<Reply>) {
        var timeout: Runnable? = null
    }

    private var pending: Request? = null

    // Entry points and completion handlers run on the method channel's main thread.
    fun read(
        requestStatus: ((Int) -> Unit) -> Unit,
        onSuccess: (Int) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        val reply = Reply(onSuccess, onError)
        pending?.let {
            it.replies.add(reply)
            return
        }

        val request = Request(mutableListOf(reply))
        pending = request
        val timeout = Runnable { finish(request) { it.success(UNKNOWN) } }
        request.timeout = timeout
        try {
            postDelayed(timeout, TIMEOUT_MS)
            requestStatus { code ->
                post(Runnable { finish(request) { it.success(code) } })
            }
        } catch (error: Throwable) {
            finish(request) { it.error(error) }
        }
    }

    fun cancel() {
        pending?.let { request -> finish(request) { it.success(UNKNOWN) } }
    }

    private fun finish(request: Request, deliver: (Reply) -> Unit) {
        if (pending !== request) return
        pending = null
        request.timeout?.let(removeCallbacks)
        request.replies.forEach(deliver)
    }

    companion object {
        private const val UNKNOWN = -1
        // The bundled SDK allows five seconds for its read callback.
        internal const val TIMEOUT_MS = 6_500L
    }
}
