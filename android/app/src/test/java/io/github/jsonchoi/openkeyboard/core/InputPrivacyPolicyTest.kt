package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.*
import org.junit.Test

class InputPrivacyPolicyTest {
    @Test fun hostSecurityFlagsBlockReads() {
        assertTrue(InputPrivacyPolicy.blocksEditor(null))
        for (type in listOf(0, 2, 3, 4, 0x81, 0x91, 0xe1, 0x12, 0x21, 0xd1, 0x71)) assertTrue(type.toString(), InputPrivacyPolicy.blocksEditor(type))
        assertTrue(InputPrivacyPolicy.blocksEditor(1, 0x01000000))
        for (hint in listOf("Password", "비밀번호", "認証コード", "验证码", "驗證碼", "Card number", "계좌번호", "여권 번호", "Passport")) assertTrue(hint, InputPrivacyPolicy.blocksEditor(1, hint = hint))
        assertFalse(InputPrivacyPolicy.blocksEditor(1))
        assertFalse(InputPrivacyPolicy.blocksEditor(0x20001)) // ordinary multiline text
        assertFalse(InputPrivacyPolicy.blocksEditor(1, hint = "메시지 입력"))
    }
}
