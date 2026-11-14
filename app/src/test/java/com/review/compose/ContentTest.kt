package com.review.compose

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDateTime

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ContentTest {
    @Test fun commentPhotoPagesResolveOnlyTrustedImages() {
        val page = "https://photo.weibo.com/h5/comment/compic_id/1022:2305974e19620d09b6e958141338527c378046"
        assertTrue(isCommentPhotoPage(page))
        assertFalse(isCommentPhotoPage(page.replace("photo.weibo.com", "photo.weibo.com.example.org")))
        assertFalse(isCommentPhotoPage("https://photo.weibo.com/h5/comment/compic_id/invalid"))
        val image = "https://wx1.sinaimg.cn/bmiddle/006AMmvKgy1ij1y25qoijj32c0340npd.jpg"
        assertEquals(image, commentPhotoImage("<div class='img-box'><img src='$image'></div>"))
        assertNull(commentPhotoImage("<div class='img-box'><img src='https://evil.example/a.jpg'></div>"))
        assertNull(commentPhotoImage("<title>登录</title>"))
    }
    @Test fun officialWebLinksReuseNativeDestinations() {
        assertEquals("place:8008644030000000000", officialWebRoute("https://weibo.com/p/1001018008644030000000000"))
        assertEquals("place:B2094653D36BA1FB409B", officialWebRoute("https://m.weibo.cn/p/index?containerid=100101B2094653D36BA1FB409B"))
        assertEquals("440300", placeRegionCode("8008644030000000000"))
        assertEquals("trends", officialWebRoute("https://weibo.com/hot/search/"))
        assertEquals("messages", officialWebRoute("https://api.weibo.com/chat/#/chat"))
        assertEquals("relations:123:false", officialWebRoute("https://weibo.com/u/123/fans"))
        assertEquals("searchResults:night%20sky", officialWebRoute("https://s.weibo.com/weibo?q=night%20sky"))
        assertNull(officialWebRoute("https://weibo.com.example.com/p/1001018008644030000000000"))
        assertNull(officialWebRoute("https://weibo.com/u/123/unrelated"))
    }

    @Test fun detailRetainsVisibleShortLinksOnlyOnTheMatchingStatus() {
        val url = "http://t.cn/R2WxEin"
        val oldQuote = Post("12", "原作者", text = "原帖\n$url")
        val newQuote = oldQuote.copy(text = "更新正文", images = listOf(Media(artwork = 1), Media(artwork = 2)))
        val source = Post("13", "转发作者", text = "转发内容", repost = oldQuote)
        val fresh = source.copy(repost = newQuote)
        val retained = retainStatusShortLinks(source, fresh)
        assertEquals("转发内容", retained.text)
        assertEquals("更新正文\n$url", retained.repost?.text)
        assertEquals(2, retained.repost?.images?.size)
        assertEquals(retained, retainStatusShortLinks(source, retained))
        assertEquals(newQuote.copy(id = "14"), retainStatusShortLinks(oldQuote, newQuote.copy(id = "14")))
    }

    @Test fun photoPreviewGeometryUsesFlutterMetadataWithoutChangingTheFullImage() {
        val info = JSONObject("""{"largest":{"width":743,"height":1210},"large":{"url":"https://wx1.sinaimg.cn/large/a.jpg"}}""")
        val photo = pictureMedia(info, "https://wx1.sinaimg.cn/large/a.jpg")
        assertEquals(743, photo.width)
        assertEquals(1210, photo.height)
        assertEquals(1f, photo.thumbnailAspect)
        info.getJSONObject("large").put("geo", JSONObject("""{"width":400,"height":800}"""))
        val narrow = pictureMedia(info, photo.url)
        assertEquals(.5f, narrow.thumbnailAspect)
        assertEquals(photo.width, narrow.width)
        assertEquals(photo.height, narrow.height)
    }

    @Test fun picturesWithoutAnIdArrayAndOlderSnapshotsKeepTheirPreviewGeometry() {
        val post = parsePost(JSONObject("""{"idstr":"7","text_raw":"图片","pic_infos":{"a":{"largest":{"url":"https://wx1.sinaimg.cn/large/a.jpg","width":743,"height":1210}}}}"""))
        assertEquals(1, post.images.size)
        assertEquals(1f, post.images.single().thumbnailAspect)
        assertEquals(post.images, Post.restore(post.snapshot()).images)
        val older = post.snapshot()
        older.getJSONArray("images").getJSONObject(0).remove("thumbnailAspect")
        assertEquals(post.images, Post.restore(older).images)
        for (invalid in listOf("NaN", "Infinity", "1000", "-2")) {
            older.getJSONArray("images").getJSONObject(0).put("thumbnailAspect", invalid)
            assertEquals(0f, Post.restore(older).images.single().thumbnailAspect)
        }
        assertEquals("21.0万", parseUser(JSONObject("""{"followers_count":210000,"followers_count_str":"21万"}""")).followers)
        assertEquals("21.0万", compactCount("21万"))
        assertEquals("21.5万", compactCount("21.5万"))
    }
    @Test fun commentIdsAcceptOfficialAliasesAndSkipNullCandidates() {
        listOf("cid", "cidstr", "comment_id", "comment_idstr", "commentId", "commentIdStr", "mid").forEach { key ->
            val value = JSONObject().put("id", JSONObject.NULL).put(key, "12345").put("text", "评论")
            assertEquals("12345", parseComment(value).id)
        }
    }

    @Test fun retweetAttachmentsUseExactOuterLinksAndKeepTheOriginalSeparate() {
        val value = JSONObject("""{"id":"1","text_raw":"附图 https://t.cn/one",
          "url_struct":[{"short_url":"http://t.cn/one","url_title":"查看图片","ori_url":"https://photo.weibo.com/h5/repost/reppic_id/1",
            "pic_infos":{"outer":{"largest":{"url":"http://wx1.sinaimg.cn/large/outer.jpg","width":10,"height":20}}}},
            {"short_url":"https://t.cn/on","pic_infos":{"wrong":{"largest":{"url":"https://wx1.sinaimg.cn/large/wrong.jpg"}}}}],
          "retweeted_status":{"id":"2","pics":[{"url":"https://wx1.sinaimg.cn/large/original.jpg"}]}}""")
        val post = parsePost(value)
        assertEquals("https://wx1.sinaimg.cn/large/outer.jpg", post.images.single().url)
        assertEquals("附图", post.text)
        assertEquals("https://wx1.sinaimg.cn/large/original.jpg", post.repost!!.images.single().url)
        assertEquals(post.images, Post.restore(post.snapshot()).images)
        value.put("text_raw", "").put("text", "<a href='https://t.cn/one'>查看图片</a>")
        assertEquals(post.images, parsePost(value).images)
    }

    @Test fun qualityMenuUsesExplicitTiersAndDeduplicatesStreams() {
        val values = linkedMapOf("mp4_1080p_mp4" to "https://example.com/full.mp4", "1080P" to "https://example.com/full.mp4",
            "720p" to "https://example.com/720.mp4", "高清" to "https://example.com/hd.mp4", "默认" to "https://example.com/full.mp4")
        assertEquals(mapOf("1080P" to "https://example.com/full.mp4", "720P" to "https://example.com/720.mp4"), normalizeVideoQualities(values, values.getValue("高清")))
        assertEquals(mapOf("分辨率未知" to "https://example.com/hd.mp4"), normalizeVideoQualities(mapOf("高清" to values.getValue("高清")), ""))
    }
    @Test fun videoAttachmentsMergeByObjectIdWhileKeepingDistinctVideos() {
        val post = parsePost(JSONObject("""{
          "idstr":"5362284863951441",
          "page_info":{"page_id":"1022:1034:first","page_pic":"https://example.com/cover.jpg",
            "media_info":{"stream_url":"https://a.weibocdn.com/first.mp4?token=old","width":1280,"height":720}},
          "url_struct":[{"long_url":"https://t.cn/short","h5_target_url":"https://h5.video.weibo.com/show/1034:first"},
            {"long_url":"https://h5.video.weibo.com/show/1034:second"}]
        }"""))
        assertEquals(listOf("1034:first", "1034:second"), post.images.map(Media::videoId))
        val first = post.images.first()
        assertEquals("https://a.weibocdn.com/first.mp4?token=old", first.video)
        assertEquals("https://example.com/cover.jpg", first.url)
        assertEquals(1280, first.width)
        assertEquals(post.images, Post.restore(post.snapshot()).images)

        val renewed = Media(video = "https://b.weibocdn.com/first.mp4?token=new")
        val merged = mergeStatusMedia(post.images, listOf(renewed))
        assertEquals(2, merged.size)
        assertEquals(renewed.video, merged.first().video)
        assertEquals(first.url, merged.first().url)
        assertEquals(first.videoId, merged.first().videoId)
        assertEquals(2, mergeStatusMedia(listOf(first), listOf(renewed.copy(videoId = "1034:different"))).size)
    }

    @Test fun hdrThumbnailHintIsBoundedAndRestrictedToOriginalImageHosts() {
        assertTrue(isHdrProbeUrl("https://wx1.sinaimg.cn/large/image.jpg"))
        listOf("https://wx1.sinaimg.cn.evil.test/large/image.jpg", "http://wx1.sinaimg.cn/large/image.jpg", "https://wx1.sinaimg.cn/thumbnail/image.jpg", "https://user@wx1.sinaimg.cn/large/image.jpg").forEach { assertFalse(isHdrProbeUrl(it)) }
        val marker = "http://ns.adobe.com/hdr-gain-map/1.0/".toByteArray()
        assertFalse(mayContainHdrGainMap(marker))
        assertTrue(mayContainHdrGainMap(byteArrayOf(0xff.toByte(), 0xd8.toByte()) + marker))
        val late = ByteArray(262144).apply { this[0] = 0xff.toByte(); this[1] = 0xd8.toByte() } + marker
        assertFalse(mayContainHdrGainMap(late))
    }
    @Test fun mediaBadgesKeepTheirMetadataThroughSavedSnapshots() {
        val photo = pictureMedia(JSONObject("""{"is_long":true,"largest":{"width":100,"height":300}}"""), "https://example.com/image.jpg")
        assertTrue(photo.long)
        val video = videoMedia(JSONObject("""{"media_info":{"stream_url":"https://example.com/video.mp4","duration":125}}"""))!!
        assertEquals("02:05", video.duration)
        assertEquals("1:23", mediaDuration("1:23"))
        assertEquals("", mediaDuration(-1))
        val post = Post("1", "A", text = "", images = listOf(photo, video, Media(gif = true)))
        assertEquals(post, Post.restore(JSONObject(post.snapshot().toString())))
    }
    @Test fun groupQrContainsTheOriginalJoinLink() {
        val matrix = groupQrCode("123456789")
        val size = (matrix.width + 8) * 8
        val pixels = IntArray(size * size) { -1 }
        for (y in 0 until matrix.height) for (x in 0 until matrix.width) if (matrix[x, y]) {
            for (dy in 0 until 8) for (dx in 0 until 8) pixels[((y + 4) * 8 + dy) * size + (x + 4) * 8 + dx] = android.graphics.Color.BLACK
        }
        val bitmap = com.google.zxing.BinaryBitmap(com.google.zxing.common.HybridBinarizer(com.google.zxing.RGBLuminanceSource(size, size, pixels)))
        assertEquals("https://weibo.com/p/230491123456789", com.google.zxing.qrcode.QRCodeReader().decode(bitmap).text)
    }
    @Test fun groupMemberUidAndNickAreNotDiscardedAsAnEmptyUser() {
        val original = JSONObject().put("uid", "123").put("nick", "群友").put("avatar", "https://example.com/avatar.jpg")
        val user = parseGroupMember(original)
        assertEquals("123", user.id); assertEquals("群友", user.name); assertEquals("https://example.com/avatar.jpg", user.avatar)
        assertFalse(original.has("id"))
    }
    @Test fun chatMediaCaptionsDoNotShowTransportPlaceholders() {
        assertEquals("", chatCaption("[图片]", true, false))
        assertEquals("", chatCaption("分享视频", false, true))
        assertEquals("[图片]", chatCaption("[图片]", false, false))
        assertEquals("今天的照片", chatCaption("今天的照片", true, false))
        assertEquals(java.time.Instant.ofEpochSecond(1234567890), chatTimestamp("1234567890"))
    }
    @Test fun confirmedLikeUpdatesCountWithoutChangingThePreviousSnapshot() {
        val before = parsePost(JSONObject().put("id", "1").put("text_raw", "正文").put("attitudes_count", 3))
        val after = before.withInteraction("like", true)
        assertFalse(before.liked); assertEquals(3, before.likes); assertEquals(3, before.data.getInt("attitudes_count"))
        assertTrue(after.liked); assertEquals(4, after.likes)
        assertEquals(4, after.withInteraction("like", true).likes)
        assertEquals(3, after.withInteraction("like", false).likes)
        assertEquals(4, after.withInteraction("favorite", true).likes)
    }
    @Test fun topicFeedsAcceptBothOfficialResponseShapes() {
        val status = JSONObject().put("id", "123").put("text_raw", "正文")
        val direct = JSONObject().put("items", org.json.JSONArray().put(JSONObject().put("data", status)).put(JSONObject().put("data", JSONObject().put("title", "广告"))))
        assertEquals(listOf("123"), topicStatusData(direct).map { it.getString("id") })
        val fallback = JSONObject().put("data", JSONObject().put("statuses", org.json.JSONArray().put(status)))
        assertEquals(listOf("123"), topicStatusData(fallback).map { it.getString("id") })
    }
    @Test fun signedVideoObjectKeepsNativePlayerAndLiveCardIsNotAWebPicture() {
        val status = parsePost(JSONObject("""{"id":"1","text_raw":"watch https://t.cn/test","url_objects":[{"url_ori":"https://t.cn/test","object_id":"1034:123","info":{"title":"watch"},"object":{"target_url":"https://h5.video.weibo.com/show/1034:123","object":{"object_type":"video","image":{"url":"https://example.com/cover.jpg"},"urls":{"720P":"https://example.com/signed.mp4?token=abc"}}}}]}"""))
        assertEquals("https://example.com/signed.mp4?token=abc", status.images.single().video)
        assertEquals("https://example.com/cover.jpg", status.images.single().url)
        val live = parsePost(JSONObject("""{"id":"2","text_raw":"live","page_info":{"page_url":"https://weibo.com/l/wblive/p/show/123","page_pic":{"url":"https://example.com/live.jpg"}},"url_struct":[{"long_url":"https://weibo.com/l/wblive/p/show/123","url_type":39,"card_image_url":"https://example.com/live.jpg"}]}"""))
        assertEquals(1, live.images.size)
        assertTrue(live.images.single().video.contains("wblive"))
        assertFalse(live.images.single().card)
    }
    @Test fun cardHydrationPreservesBackdropAndRemovesOnlyGeneratedCovers() {
        val card = Media("https://example.com/foreground.png", background = "https://example.com/background.jpg", width = 1600, height = 900, card = true)
        val merged = mergeStatusMedia(listOf(card), listOf(card.copy(background = "", width = 0, height = 0)))
        assertEquals(card, merged.single())
        val photo = Media("https://example.com/real.jpg")
        val video = Media("https://example.com/cover.jpg", video = "https://example.com/video.mp4")
        assertEquals(listOf(photo, video), mergeStatusMedia(listOf(card, photo), listOf(video)))
    }
    @Test fun encodedEmojiAndProfileFiltersRetainOriginalSemantics() {
        assertEquals("☀", encodedEmoji("[ee818a.png]", JSONObject().put("57418", "☀")))
        assertNull(encodedEmoji("[ffffff.png]", JSONObject()))
        val post = Post("1", "name", "7", text = "text", time = "2026-10-03T12:00:00")
        assertTrue(matchesProfilePost(post, "7", false, 2026, 10))
        assertFalse(matchesProfilePost(post, "7", false, 2026, 11))
        assertFalse(matchesProfilePost(post.copy(uid = "8"), "7", false, 0, 0))
        assertTrue(matchesProfilePost(post.copy(uid = "8"), "7", true, 0, 0))
    }
    @Test fun privateChatAttachmentsUseExactHostAndNamedJsonpOnly() {
        val message = JSONObject("""{"media_type":1,"att_ids":["a","a","b"]}""")
        assertEquals(2, chatImages(message).size)
        assertEquals("secret", MediaFiles.privateMediaCookie(chatAttachmentUrl("a"), "secret"))
        assertEquals("", MediaFiles.privateMediaCookie("https://upload.api.weibo.com.evil.example/2/mss/msget", "secret"))
        assertEquals("", MediaFiles.privateMediaCookie("https://upload.api.weibo.com/other", "secret"))
        assertEquals("mp4", chatMetadata("__review_video_meta({\"extension\":\"mp4\"});").optString("extension"))
        assertEquals(0, chatMetadata("arbitrary({\"extension\":\"mp4\"});").length())
        assertNull(chatVideo(JSONObject().put("media_type", "10"), "a", JSONObject().put("is_delete", true)))
    }
    @Test fun nestedReplyDropsInheritedPictureButKeepsItsOwnAttachment() {
        val root = parseComment(JSONObject("""{"id":"1","user":{"id":"9"},"pic":{"large":{"url":"https://wx1.sinaimg.cn/large/same.jpg"}},"comments":[{"id":"2","user":{"id":"10"},"pics":[{"large":{"url":"https://wx1.sinaimg.cn/bmiddle/same.jpg"}},{"large":{"url":"https://wx1.sinaimg.cn/large/own.jpg"}}]}]}"""))
        assertEquals(1, root.children[0].images.size)
        assertTrue(root.children[0].images[0].url.endsWith("own.jpg"))
        assertFalse(root.replyCountKnown)
    }
    @Test fun videoLinksRejectForeignHostsAndNeverPlayHtmlShells() {
        assertEquals("1034:123", videoObjectId("https://h5.video.weibo.com/show/1034:123"))
        assertEquals("1034:123", videoObjectId("https://video.weibo.com/show?fid=1034%3A123"))
        assertNull(videoObjectId("https://evil.example/show/1034:123"))
        assertEquals("", playableVideo("https://h5.video.weibo.com/show/1034:123"))
        val media = parseVideoComponent(JSONObject("""{"data":{"Component_Play_Playinfo":{"title":"Video","urls":{"720P":{"url":"//example.com/v.mp4"},"shell":"https://h5.video.weibo.com/show/1034:123"}}}}"""))!!
        assertEquals("https://example.com/v.mp4", media.video)
        assertEquals(1, media.qualities.size)
    }
    @Test fun pollShellDoesNotInventResultsAndNestedPollKeepsOptions() {
        val status = JSONObject("""{"id":"90","url_objects":[{"object":{"object":{"content":"Choose","user_nick":"Author","vote_object":{"id":"7","is_multi_select":1,"vote_list":[{"id":"a","title":"A"},{"id":"b","title":"B"}]}}}}]}""")
        val poll = parsePoll(status)!!
        assertEquals("7", poll.id); assertTrue(poll.multiple); assertFalse(poll.hasResults)
        assertEquals(listOf("a", "b"), poll.options.map { it.id })
        val vote = status.getJSONArray("url_objects").getJSONObject(0).getJSONObject("object").getJSONObject("object").getJSONObject("vote_object")
        vote.getJSONArray("vote_list").getJSONObject(0).put("part_num", 10).put("part_ratio", .25)
        assertEquals(25.0, parsePoll(status)!!.options[0].percent!!, .01)
        assertTrue(parsePoll(status)!!.hasResults)
        assertNull(parsePoll(JSONObject("""{"page_info":{"type":"video","title":"Video","items":["a","b"]}}""")))
    }
    @Test fun articleLinksAreRestrictedAndArticleParserExcludesShellAndScripts() {
        assertEquals("123", articleId("https://weibo.com/ttarticle/p/show?id=123"))
        assertEquals("123", articleId("https://weibo.com/article/m/show/id/123"))
        assertNull(articleId("https://evil.example/ttarticle/p/show?id=123"))
        val document = parseArticle("""<html><title>Shell</title><h1 node-type="articleTitle">Actual title</h1><div node-type="contentBody"><p>Hello <a href="https://example.com">world</a></p><figure><img src="//images.example/a.jpg" width="400" height="200"><figcaption>Caption</figcaption></figure><script>bad()</script><h2>Heading</h2></div></html>""")
        assertEquals("Actual title", document.title)
        assertEquals(3, document.blocks.size)
        assertEquals("Hello world", document.blocks[0].text)
        assertEquals("https://images.example/a.jpg", document.blocks[1].image)
        assertEquals(1.5f, document.blocks[1].ratio)
        assertTrue(document.blocks[2].heading)
        assertTrue(parseArticle("<title>Login</title><body>Sign in</body>").blocks.isEmpty())
    }
    @Test fun articlePreservesOriginalAspectSourceSelectionAndStandaloneLinks() {
        val document = parseArticle("""<img node-type="articleHeaderPic" data-src="/cover.jpg"><div node-type="contentBody"><a data-href="/u/123">作者主页</a><p>前文 <a href="javascript:alert(1)">普通文字</a> <a href="http://example.com/page">链接</a></p><figure><a><img aspect="2" width="100" height="400" srcset="//example.com/s.jpg 320w, //example.com/m.jpg 1024w, //example.com/l.jpg 2048w"></a><figcaption>图说</figcaption></figure><img aspect="NaN" data-original="/original.jpg" data-src="/small.jpg"></div>""")
        assertEquals("https://weibo.com/cover.jpg", document.cover)
        assertEquals("https://weibo.com/u/123", document.blocks[0].inlines.single().url)
        assertEquals("https://example.com/page", document.blocks[1].inlines.single { it.url.isNotBlank() }.url)
        assertEquals("https://example.com/m.jpg", document.blocks[2].image)
        assertEquals(2f, document.blocks[2].ratio)
        assertEquals("图说", document.blocks[2].caption)
        assertEquals("https://weibo.com/original.jpg", document.blocks[3].image)
        assertEquals(1.5f, document.blocks[3].ratio)
    }
    @Test fun textKeepsEmojiAndOfficialVideoAnchorTarget() {
        val text = cleanRichHtml("Hi<img alt='[微笑]' src='x'><br><a href='https://video.weibo.com/show?fid=123'>Video</a>")
        assertTrue(text.contains("[微笑]")); assertTrue(text.contains("https://video.weibo.com/show?fid=123"))
    }
    @Test fun expandedLongTextPreservesPlainAndHtmlParagraphs() {
        assertEquals("第一段。\n\n第二段。", cleanLongText("第一段。\r\n\r\n第二段。"))
        assertEquals("第一段。[微笑]\n\n第二段。", cleanLongText("第一段。<img alt='[微笑]' src='x'>\n\n第二段。"))
        assertEquals("第一段。\n\n第二段。", cleanLongText("<span>第一段。</span><br><br><span>第二段。</span>"))
        val post = parsePost(JSONObject("""{"id":"1","isLongText":true,"text_raw":"第一段。","longTextContent":"第一段。<br><br>第二段。"}"""))
        assertEquals("第一段。\n\n第二段。", post.availableFullText())
    }
    @Test fun mixedMediaOrderAndCardMetadataSurviveSnapshots() {
        val post = parsePost(JSONObject("""{"id":"1","text_raw":"Text","user":{"screen_name":"A"},"mix_media_info":{"items":[{"type":"video","data":{"page_pic":"https://example.com/cover.jpg","media_info":{"stream_url":"https://example.com/video.mp4"}}},{"type":"pic","data":{"pic_info":{"largest":{"url":"https://example.com/photo.jpg","width":100,"height":200}}}}]},"url_struct":[{"url_type":39,"pic_url":"https://example.com/card.png","media_pic_url":"https://example.com/background.jpg","url_title":"Birthday"}]}"""))
        assertTrue(post.images[0].video.isNotBlank()); assertEquals(200, post.images[1].height)
        assertTrue(post.images[2].card); assertEquals("Birthday", post.images[2].title)
        assertEquals(post, Post.restore(JSONObject(post.snapshot().toString())))
    }
    @Test fun relativeTimeHandlesMonthBoundaryWithoutChangingAbsoluteMode() {
        val now = LocalDateTime.of(2026, 11, 1, 12, 0)
        assertEquals("昨天 13:00", postTime("2026-10-31T13:00:00", true, false, false, false, false, now))
        assertEquals("2026年10月31日 13:00:00 +0800", postTime("2026-10-31T13:00:00", false, false, true, true, true, now))
    }
}
