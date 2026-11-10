package com.review.compose

import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import org.junit.Assert.assertEquals
import org.junit.Test

class EditorTest {
    @Test fun declarationLabelsUseOriginalCompactText() {
        assertEquals("转载", declarationShortLabel("转载来源"))
        assertEquals("创作", declarationShortLabel("自主创作"))
        assertEquals("AI", declarationShortLabel("人工智能生成"))
        assertEquals("AI", declarationShortLabel("含 ai 生成内容"))
        assertEquals("虚构", declarationShortLabel("剧情演绎"))
        assertEquals("无声明", declarationShortLabel(" "))
        assertEquals("其他说明", declarationShortLabel(" 其他说明 "))
    }
    @Test fun decodesStatusLinksInFourCharacterChunks() {
        assertEquals("5339420032499899", numericStatusId("RgxuHaukX"))
        assertEquals("1234567890123456", numericStatusId(" 1234567890123456 "))
        assertEquals("", numericStatusId("https://example.com"))
        assertEquals("10000", numericStatusId("10000"))
    }
    @Test fun insertsAtSelectionAndRemovesWholePhrase() {
        val inserted = TextFieldValue("前删除后", TextRange(1, 3)).insertPhrase("[微笑]")
        assertEquals("前[微笑]后", inserted.text)
        assertEquals(TextRange(5), inserted.selection)
        assertEquals(TextFieldValue("前后", TextRange(1)), inserted.erasePhrase())
    }
    @Test fun backspacePreservesSurrogatePairsAndSelection() {
        assertEquals("后", TextFieldValue("😀后", TextRange(2)).erasePhrase().text)
        assertEquals("前后", TextFieldValue("前选中后", TextRange(3, 1)).erasePhrase().text)
        assertEquals("前", TextFieldValue("前", TextRange.Zero).erasePhrase().text)
    }
}
