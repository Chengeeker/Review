package com.review.compose

import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.io.OutputStream
import java.security.KeyStore
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.net.ssl.*
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class WebDavTransportTest {
    private var removedProviders:List<Pair<Int,java.security.Provider>> = emptyList()
    @org.junit.Before fun hostTlsProviders(){
        removedProviders=java.security.Security.getProviders().mapIndexedNotNull{index,provider->if(provider.javaClass.name.contains("conscrypt",true))index+1 to provider else null}
        removedProviders.forEach{java.security.Security.removeProvider(it.second.name)}
    }
    @org.junit.After fun restoreProviders(){removedProviders.forEach{java.security.Security.insertProviderAt(it.second,it.first)}}
    private val auth = Credentials.basic("synthetic-user", "synthetic-password")
    private class Headers {
        private val values=linkedMapOf<String,String>()
        fun add(name:String,value:String){values[name.lowercase()]=value}
        fun getFirst(name:String)=values[name.lowercase()]
        fun lines()=values.entries.joinToString("") { "${it.key}: ${it.value}\r\n" }
    }
    private class Exchange(private val socket:Socket) {
        val requestHeaders=Headers()
        val responseHeaders=Headers()
        val requestURI:URI
        val responseBody:OutputStream=socket.getOutputStream()
        init {
            socket.soTimeout=5000
            val input=socket.getInputStream().bufferedReader(Charsets.ISO_8859_1)
            requestURI=URI(input.readLine().split(' ')[1])
            while(true){val line=input.readLine()?:break;if(line.isEmpty())break
                val colon=line.indexOf(':');requestHeaders.add(line.substring(0,colon),line.substring(colon+1).trim())}
            // PUT fixtures have tiny bodies. Consume them before the reply.
            val length=requestHeaders.getFirst("Content-Length")?.toIntOrNull()?:0
            repeat(length){input.read()}
        }
        fun sendResponseHeaders(code:Int,length:Long){
            if(length!=0L)responseHeaders.add("Content-Length",length.coerceAtLeast(0).toString())
            responseHeaders.add("Connection","close")
            responseBody.write(("HTTP/1.1 $code Fixture\r\n"+responseHeaders.lines()+"\r\n").toByteArray(Charsets.ISO_8859_1))
            responseBody.flush()
        }
    }
    private class Server(tls: SSLContext? = null) : AutoCloseable {
        @Volatile var handle: (Exchange) -> Unit = { reply(it, 200, "{}") }
        private val failure=java.util.concurrent.atomic.AtomicReference<Throwable?>()
        private val executor = Executors.newCachedThreadPool { work -> Thread(work).apply { isDaemon = true } }
        private val server = tls?.serverSocketFactory?.createServerSocket(0,50,java.net.InetAddress.getByName("127.0.0.1"))
            ?: ServerSocket(0,50,java.net.InetAddress.getByName("127.0.0.1"))
        val port get()=server.localPort
        private val origin="${if(tls==null)"http"else"https"}://localhost:$port"
        init { executor.execute {
            while(!server.isClosed) {
                val socket=try{server.accept()}catch(_:java.io.IOException){break}
                executor.execute {socket.use{try{handle(Exchange(it));it.getOutputStream().flush()}
                    catch(e:AssertionError){failure.compareAndSet(null,e)}
                    catch(_:java.io.IOException){}catch(_:InterruptedException){}}}
            }
        } }
        fun url(path:String="/backup.json")="$origin$path".toHttpUrl()
        override fun close(){server.close();executor.shutdownNow();failure.get()?.let{throw it}}
    }

    @Test fun connectionAndAllDownloadRedirectsKeepSignatureAndSameOriginAuthorization() = runBlocking {
        Server().use { server ->
            val transport = WebDavTransport(plainClient(), 1024)
            server.handle = { reply(it, 207) }
            assertEquals(207, transport.request(server.url(), "PROPFIND", auth).code)
            for (code in listOf(301, 302, 303, 307, 308)) {
                server.handle = {
                    assertEquals(auth, it.requestHeaders.getFirst("Authorization"))
                    if (it.requestURI.path == "/backup.json") redirect(it, code, "file?signature=a%2Bb%2Fz%3D")
                    else {
                        assertEquals("signature=a%2Bb%2Fz%3D", it.requestURI.rawQuery)
                        reply(it, 200, "{\"app\":\"synthetic\"}")
                    }
                }
                assertEquals("synthetic", transport.request(server.url(), "GET", auth).json().getString("app"))
            }
        }
    }

    @Test fun crossOriginDropsSecretsAndReturningToOriginDoesNotReattachThem() = runBlocking {
        val (tls, trust) = tls()
        val injected = OkHttpClient.Builder().sslSocketFactory(tls.socketFactory, trust)
            .eventListener(object:EventListener(){override fun callFailed(call:Call,ioe:java.io.IOException){System.err.println("Synthetic TLS fixture: ${ioe.javaClass.simpleName}: ${ioe.message}")}})
            .addInterceptor { chain -> chain.proceed(chain.request().newBuilder().header("Cookie", "synthetic-leak").build()) }
            .cookieJar(object : CookieJar {
                override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) = Unit
                override fun loadForRequest(url: HttpUrl) = listOf(Cookie.Builder().name("secret").value("synthetic-leak").domain(url.host).build())
            }).authenticator { _, _ -> error("Source authenticator must not run") }.build()
        Server(tls).use { origin -> Server(tls).use { cdn ->
            origin.handle = {
                assertNull(it.requestHeaders.getFirst("Cookie"))
                if (it.requestURI.path == "/backup.json") { assertEquals(auth, it.requestHeaders.getFirst("Authorization")); redirect(it, 302, cdn.url().toString()) }
                else { assertNull(it.requestHeaders.getFirst("Authorization")); reply(it, 200, "{}") }
            }
            cdn.handle = {
                assertNull(it.requestHeaders.getFirst("Authorization")); assertNull(it.requestHeaders.getFirst("Cookie"))
                assertNull(it.requestHeaders.getFirst("Proxy-Authorization"))
                redirect(it, 307, origin.url("/returned").toString())
            }
            assertEquals(200, WebDavTransport(injected, 1024).request(origin.url(), "GET", auth).code)
            cdn.handle = { reply(it, 401) }
            assertEquals(401, WebDavTransport(injected, 1024).request(cdn.url(), "GET", auth).code)
        } }
    }

    @Test fun rejectsUnsafeRedirectsMissingLocationAndLoops() = runBlocking {
        Server().use { server ->
            val transport = WebDavTransport(plainClient(), 1024)
            for (target in listOf("", "javascript:bad", "https://user:secret@example.test/file", "http://example.test/file", "/backup.json")) {
                server.handle = { redirect(it, 302, target) }
                fails { transport.request(server.url(), "GET", auth) }
            }
            server.handle = { reply(it, 302) }
            fails { transport.request(server.url(), "GET", auth) }
            server.handle = { redirect(it, 302, "/hop${it.requestURI.path.count { c -> c == 'x' } + 1}" + it.requestURI.path + "x") }
            fails { transport.request(server.url(), "GET", auth) }
        }
        val (tls, trust) = tls()
        Server(tls).use { server ->
            server.handle = { redirect(it, 302, "http://localhost:${server.port}/plain") }
            fails { WebDavTransport(OkHttpClient.Builder().sslSocketFactory(tls.socketFactory, trust).build(), 1024).request(server.url(), "GET", auth) }
        }
    }

    @Test fun failuresAreClassifiedAndWritesNeverFollowRedirects() = runBlocking {
        Server().use { server ->
            val transport = WebDavTransport(plainClient(), 1024)
            for (code in listOf(401, 403, 404, 429, 500, 503)) {
                server.handle = { reply(it, code, "private upstream text") }
                val response = transport.request(server.url(), "GET", auth)
                try { response.requireStatus("下载", setOf(200)); fail() } catch (e: IllegalStateException) {
                    assertTrue(e.message!!.contains(code.toString()))
                    assertFalse(e.message!!.contains("private"))
                    if (code != 404) assertFalse(e.message!!.contains("没有备份"))
                }
            }
            var requests = 0
            server.handle = { requests++; redirect(it, 302, "/other") }
            assertEquals(302, transport.request(server.url(), "PUT", auth, byteArrayOf(1)).code)
            assertEquals(1, requests)
        }
    }

    @Test fun boundsActualAndAdvertisedLengthsAndRejectsNonJson() = runBlocking {
        Server().use { server ->
            val transport = WebDavTransport(plainClient(), 1024)
            server.handle = { reply(it, 200, "x".repeat(1025)) }
            fails { transport.request(server.url(), "GET", auth) }
            server.handle = { it.sendResponseHeaders(200, 0); it.responseBody.write(ByteArray(1025)) }
            fails { transport.request(server.url(), "GET", auth) }
            for (body in listOf("", "<html>login</html>", "{broken")) {
                server.handle = { reply(it, 200, body) }
                fails { transport.request(server.url(), "GET", auth).json() }
            }
        }
    }

    @Test fun cancellationInterruptsAnOutstandingDownload() = runBlocking {
        Server().use { server ->
            val received = CountDownLatch(1)
            server.handle = { received.countDown(); Thread.sleep(5000); reply(it, 200, "{}") }
            val job = launch(Dispatchers.IO) { WebDavTransport(plainClient(), 1024).request(server.url(), "GET", auth) }
            assertTrue(withContext(Dispatchers.IO) { received.await(2, TimeUnit.SECONDS) })
            withTimeout(1000) { job.cancelAndJoin() }
            assertTrue(job.isCancelled)
        }
    }

    private suspend fun fails(block: suspend () -> Unit) {
        try { block(); fail("Expected refusal") } catch (e: Exception) { assertTrue(e.message.orEmpty().startsWith("WebDAV") || e.message.orEmpty().contains("大小上限")) }
    }

    private fun plainClient():OkHttpClient {val (tls,trust)=tls();return OkHttpClient.Builder().sslSocketFactory(tls.socketFactory,trust).build()}

    private fun tls(): Pair<SSLContext, X509TrustManager> {
        val store = KeyStore.getInstance("PKCS12")
        javaClass.getResourceAsStream("/webdav-synthetic.p12")!!.use { store.load(it, "synthetic-only".toCharArray()) }
        val keys = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm(),"SunJSSE").apply { init(store, "synthetic-only".toCharArray()) }
        val trusts = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm(),"SunJSSE").apply { init(store) }
        return SSLContext.getInstance("TLS","SunJSSE").apply { init(keys.keyManagers, trusts.trustManagers, null) } to trusts.trustManagers.filterIsInstance<X509TrustManager>().single()
    }

    companion object {
        private fun reply(e: Exchange, code: Int, body: String = "") {
            val bytes = body.toByteArray()
            e.sendResponseHeaders(code, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            if (bytes.isNotEmpty()) e.responseBody.write(bytes)
        }
        private fun redirect(e: Exchange, code: Int, target: String) { e.responseHeaders.add("Location", target); reply(e, code) }
    }
}
