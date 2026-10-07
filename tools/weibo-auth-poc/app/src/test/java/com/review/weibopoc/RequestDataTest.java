package com.review.weibopoc;

import static org.junit.Assert.assertEquals;

import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.Test;

public class RequestDataTest {
    @Test
    public void formEncodingUsesUtf8AndPreservesOrder() {
        Map<String, String> values = new LinkedHashMap<>();
        values.put("u", "账号 a");
        values.put("p", "x+y");

        assertEquals("u=%E8%B4%A6%E5%8F%B7+a&p=x%2By", RequestData.encode(values));
        assertEquals("https://example.test/path?a=1&u=%E8%B4%A6%E5%8F%B7%20a&p=x%2By",
                RequestData.addQuery("https://example.test/path?a=1", values));
    }
}
