package dev.lazizbekfayziev.flutter_xprinter_sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class PrinterStatusQueryTest {
    private class MainQueue {
        val posted = mutableListOf<Runnable>()
        val delayed = mutableListOf<Pair<Runnable, Long>>()
        val query = PrinterStatusQuery(
            post = { posted.add(it) },
            postDelayed = { task, delay -> delayed.add(task to delay) },
            removeCallbacks = { task -> delayed.removeAll { it.first === task } },
        )

        fun idle() {
            while (posted.isNotEmpty()) posted.removeAt(0).run()
        }

        fun timeOut() {
            delayed.toList().forEach { it.first.run() }
        }
    }

    private class Reply {
        val values = mutableListOf<Int>()
        val errors = mutableListOf<Throwable>()
    }

    @Test
    fun `main-thread callback can execute after read returns`() {
        val main = MainQueue()
        val reply = Reply()
        main.query.read(
            requestStatus = { callback -> main.posted.add(Runnable { callback(32) }) },
            onSuccess = { reply.values.add(it) },
            onError = { reply.errors.add(it) },
        )

        assertTrue(reply.values.isEmpty())
        assertEquals(PrinterStatusQuery.TIMEOUT_MS, main.delayed.single().second)
        main.idle()
        assertEquals(listOf(32), reply.values)
        assertTrue(main.delayed.isEmpty())
    }

    @Test
    fun `timeout returns unknown once and ignores late callbacks`() {
        val main = MainQueue()
        val reply = Reply()
        lateinit var callback: (Int) -> Unit
        main.query.read({ callback = it }, reply.values::add, reply.errors::add)

        main.timeOut()
        callback(0)
        main.idle()
        main.timeOut()

        assertEquals(listOf(-1), reply.values)
        assertTrue(reply.errors.isEmpty())
        assertTrue(main.delayed.isEmpty())
    }

    @Test
    fun `duplicate vendor callbacks only reply once`() {
        val main = MainQueue()
        val reply = Reply()
        main.query.read({ callback -> callback(32); callback(0) }, reply.values::add, reply.errors::add)
        main.idle()
        main.timeOut()
        assertEquals(listOf(32), reply.values)
    }

    @Test
    fun `overlapping callers share one vendor read`() {
        val main = MainQueue()
        val first = Reply()
        val second = Reply()
        lateinit var callback: (Int) -> Unit
        var reads = 0
        main.query.read({ reads++; callback = it }, first.values::add, first.errors::add)
        main.query.read({ reads++ }, second.values::add, second.errors::add)
        callback(32)
        main.idle()

        assertEquals(1, reads)
        assertEquals(listOf(32), first.values)
        assertEquals(listOf(32), second.values)
    }

    @Test
    fun `completed status is not cached for the next query`() {
        val main = MainQueue()
        val reply = Reply()
        main.query.read({ it(32) }, reply.values::add, reply.errors::add)
        main.idle()
        main.query.read({ it(0) }, reply.values::add, reply.errors::add)
        main.idle()
        assertEquals(listOf(32, 0), reply.values)
    }

    @Test
    fun `native exception fails all waiters and removes deadline`() {
        val main = MainQueue()
        val first = Reply()
        val second = Reply()
        val error = IllegalStateException("native read failed")
        main.query.read(
            requestStatus = {
                main.query.read({}, second.values::add, second.errors::add)
                throw error
            },
            onSuccess = first.values::add,
            onError = first.errors::add,
        )
        main.timeOut()

        assertSame(error, first.errors.single())
        assertSame(error, second.errors.single())
        assertTrue(first.values.isEmpty())
        assertTrue(second.values.isEmpty())
        assertTrue(main.delayed.isEmpty())
    }

    @Test
    fun `cancel settles pending callers as unknown before a new connection`() {
        val main = MainQueue()
        val first = Reply()
        val second = Reply()
        lateinit var callback: (Int) -> Unit
        main.query.read({ callback = it }, first.values::add, first.errors::add)
        main.query.read({}, second.values::add, second.errors::add)

        main.query.cancel()
        callback(0)
        main.idle()
        main.query.cancel()

        assertEquals(listOf(-1), first.values)
        assertEquals(listOf(-1), second.values)
        assertTrue(main.delayed.isEmpty())
    }

    @Test
    fun `callback from an old connection cannot complete a new request`() {
        val main = MainQueue()
        val old = Reply()
        val current = Reply()
        lateinit var oldCallback: (Int) -> Unit
        lateinit var currentCallback: (Int) -> Unit
        main.query.read({ oldCallback = it }, old.values::add, old.errors::add)
        main.query.cancel()
        main.query.read({ currentCallback = it }, current.values::add, current.errors::add)

        oldCallback(0)
        main.idle()
        assertTrue(current.values.isEmpty())
        assertFalse(main.delayed.isEmpty())
        currentCallback(32)
        main.idle()

        assertEquals(listOf(-1), old.values)
        assertEquals(listOf(32), current.values)
    }

    @Test
    fun `a queued ready response cannot win after disconnect`() {
        val main = MainQueue()
        val reply = Reply()
        main.query.read({ it(0) }, reply.values::add, reply.errors::add)
        main.query.cancel()
        main.idle()
        assertEquals(listOf(-1), reply.values)
    }

    @Test
    fun `throwing after a synchronous callback does not double reply`() {
        val main = MainQueue()
        val reply = Reply()
        val error = IllegalStateException("read failed after callback")
        main.query.read({ it(0); throw error }, reply.values::add, reply.errors::add)
        main.idle()
        main.timeOut()

        assertSame(error, reply.errors.single())
        assertTrue(reply.values.isEmpty())
    }
}
