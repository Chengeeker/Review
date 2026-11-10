package com.review.compose

fun numericStatusId(input: String): String {
    val value = input.trim()
    if (value.all(Char::isDigit)) return value
    val alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if (value.length > 32 || value.any { it !in alphabet }) return ""
    return value.reversed().chunked(4).reversed().mapIndexed { index, chunk ->
        val decimal = chunk.reversed().fold(0L) { total, char -> total * 62 + alphabet.indexOf(char) }.toString()
        if (index == 0) decimal else decimal.padStart(7, '0')
    }.joinToString("")
}
